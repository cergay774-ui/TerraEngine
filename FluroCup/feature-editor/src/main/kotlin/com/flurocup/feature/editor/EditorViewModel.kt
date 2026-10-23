package com.flurocup.feature.editor

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.SystemClock
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flurocup.core.data.project.PendingImports
import com.flurocup.core.data.project.ProjectRepository
import com.flurocup.core.engine.composition.CompositionFactory
import com.flurocup.core.engine.media.AnalyzedMedia
import com.flurocup.core.engine.media.MediaAnalyzer
import com.flurocup.core.engine.media.MediaImportException
import com.flurocup.core.engine.media.ThumbnailCache
import com.flurocup.core.engine.preview.PreviewEngine
import com.flurocup.core.engine.proxy.ProxyManager
import com.flurocup.core.engine.proxy.ProxyState
import com.flurocup.core.model.AspectRatio
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project
import com.flurocup.core.model.ProxyPolicy
import com.flurocup.core.model.edit.EditCommand
import com.flurocup.core.model.edit.EditHistory
import com.flurocup.core.model.edit.MainTrackEdits
import com.flurocup.feature.editor.timeline.FrameKey
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

enum class PreviewSource { PROXY, ORIGINAL }

data class ImportProgress(val done: Int, val total: Int)

data class ClipUi(
    val clip: MediaClip,
    val needsProxy: Boolean,
    val proxy: ProxyState?,
    /** File the timeline reads its filmstrip frames from: the proxy when there is one. */
    val frameUri: String,
)

data class EditorUiState(
    val loading: Boolean = true,
    val notFound: Boolean = false,
    val project: Project? = null,
    val clips: List<ClipUi> = emptyList(),
    val importing: ImportProgress? = null,
    val previewSource: PreviewSource = PreviewSource.PROXY,
    val selectedClipId: String? = null,
    val canUndo: Boolean = false,
    val canRedo: Boolean = false,
) {
    val selectedClip: ClipUi? get() = clips.firstOrNull { it.clip.id == selectedClipId }

    val durationUs: Long get() = clips.lastOrNull()?.clip?.endUs ?: 0L

    /** Width / height of the preview frame, the same as the exported frame. */
    val previewAspect: Float get() = project?.outputAspect() ?: (9f / 16f)
}

sealed interface EditorMessage {
    /** Files that could not be imported, with the reason for each. */
    data class ImportFailed(val failures: List<MediaImportException>) : EditorMessage

    /** The playhead is not inside a clip, or too close to its edge, to split there. */
    data object CannotSplit : EditorMessage
}

@HiltViewModel
class EditorViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    @ApplicationContext context: Context,
    private val repository: ProjectRepository,
    private val pendingImports: PendingImports,
    private val analyzer: MediaAnalyzer,
    private val proxies: ProxyManager,
    private val thumbnails: ThumbnailCache,
) : ViewModel() {

    /** Navigation puts the route's `projectId` argument into the saved state. */
    private val projectId: String = checkNotNull(savedStateHandle[PROJECT_ID_KEY])

    private val _uiState = MutableStateFlow(EditorUiState())
    val uiState: StateFlow<EditorUiState> = _uiState.asStateFlow()

    private val _messages = Channel<EditorMessage>(Channel.BUFFERED)
    val messages: Flow<EditorMessage> = _messages.receiveAsFlow()

    val preview = PreviewEngine(context)

    private val history = EditHistory()

    /** Edits, undo and proxy updates all change the project; one at a time, so none is lost. */
    private val edits = Mutex()

    /** What the preview currently plays, to skip rebuilding it when nothing it shows changed. */
    private var previewKey: List<Any?>? = null
    private var previewRebuildPending = false
    private var lastSeekAt = 0L

    init {
        viewModelScope.launch {
            val project = repository.load(projectId)
            if (project == null) {
                _uiState.update { it.copy(loading = false, notFound = true) }
                return@launch
            }
            edits.withLock { setProject(project, save = false) }
            _uiState.update { it.copy(loading = false) }
            MainTrackEdits.clips(project).forEach { requestProxyIfNeeded(it) }
            val pending = pendingImports.take(projectId)
            if (pending.isNotEmpty()) import(pending.map(Uri::parse))
        }
        viewModelScope.launch {
            proxies.states.collect { onProxyStates() }
        }
        viewModelScope.launch {
            // A proxy that finishes during playback is switched to once playback stops.
            preview.isPlaying.collect { playing ->
                if (!playing && previewRebuildPending) rebuildPreview()
            }
        }
    }

    // region Playback

    val positionUs: Long get() = preview.positionUs

    fun togglePlay() = preview.togglePlay()

    fun pause() = preview.pause()

    /** Seeks while the timeline is dragged; [final] forces the last position through. */
    fun seekTo(timelineUs: Long, final: Boolean = false) {
        val now = SystemClock.uptimeMillis()
        if (!final && now - lastSeekAt < SEEK_INTERVAL_MS) return
        lastSeekAt = now
        preview.seekTo(timelineUs)
    }

    fun setPreviewSource(source: PreviewSource) {
        _uiState.update { it.copy(previewSource = source) }
        rebuildPreview()
    }

    // endregion

    // region Editing

    fun select(clipId: String?) {
        _uiState.update { it.copy(selectedClipId = clipId) }
    }

    /** Splits the selected clip, or the clip under the playhead, at [atUs]. */
    fun split(atUs: Long) {
        val state = _uiState.value
        val project = state.project ?: return
        val clip = state.selectedClip?.clip?.takeIf { atUs > it.startUs && atUs < it.endUs }
            ?: MainTrackEdits.clipAt(project, atUs)
        viewModelScope.launch {
            val done = clip != null && execute(EditCommand.Split(clip.id, atUs, newId()))
            if (!done) _messages.send(EditorMessage.CannotSplit)
        }
    }

    fun deleteSelected() {
        val id = _uiState.value.selectedClipId ?: return
        viewModelScope.launch {
            if (execute(EditCommand.Delete(id))) select(null)
        }
    }

    fun duplicateSelected() {
        val id = _uiState.value.selectedClipId ?: return
        val copyId = newId()
        viewModelScope.launch {
            if (execute(EditCommand.Duplicate(id, copyId))) select(copyId)
        }
    }

    fun trim(clipId: String, trimStartUs: Long, trimEndUs: Long) {
        viewModelScope.launch { execute(EditCommand.Trim(clipId, trimStartUs, trimEndUs)) }
    }

    fun move(clipId: String, toIndex: Int) {
        viewModelScope.launch { execute(EditCommand.Move(clipId, toIndex)) }
    }

    fun setAspectRatio(ratio: AspectRatio) {
        viewModelScope.launch { execute(EditCommand.SetAspectRatio(ratio)) }
    }

    fun replaceSelected(uri: Uri) {
        val id = _uiState.value.selectedClipId ?: return
        viewModelScope.launch {
            val media = analyzeAll(listOf(uri)).singleOrNull() ?: return@launch
            val source = sourceOf(media)
            if (execute(EditCommand.Replace(id, source))) requestProxyIfNeeded(source)
        }
    }

    fun import(uris: List<Uri>) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            val media = analyzeAll(uris)
            if (media.isEmpty()) return@launch
            val clips = media.map { m ->
                MediaClip(id = newId(), startUs = 0, source = sourceOf(m), trimStartUs = 0, trimEndUs = m.info.durationUs)
            }
            if (execute(EditCommand.AddClips(clips))) {
                clips.forEach { requestProxyIfNeeded(it) }
                _uiState.value.project?.let { if (!repository.hasThumbnail(it.id)) makeProjectThumbnail(it) }
            }
        }
    }

    fun undo() {
        viewModelScope.launch {
            edits.withLock {
                val restored = history.undo() ?: return@withLock
                preview.pause()
                setProject(restored, save = true)
            }
        }
    }

    fun redo() {
        viewModelScope.launch {
            edits.withLock {
                val current = _uiState.value.project ?: return@withLock
                val redone = history.redo(current)
                preview.pause()
                if (redone != null) setProject(redone, save = true) else refreshHistoryFlags()
            }
        }
    }

    // endregion

    /** A filmstrip frame for the timeline. */
    suspend fun frame(key: FrameKey): Bitmap? =
        thumbnails.thumbnail(Uri.parse(key.uri), key.kind, key.timeUs, maxSizePx = FRAME_SIZE_PX)

    override fun onCleared() {
        preview.release()
    }

    private suspend fun execute(command: EditCommand): Boolean = edits.withLock {
        val current = _uiState.value.project ?: return@withLock false
        val updated = history.execute(current, command) ?: return@withLock false
        preview.pause()
        setProject(updated, save = true)
        true
    }

    private suspend fun analyzeAll(uris: List<Uri>): List<AnalyzedMedia> {
        _uiState.update { it.copy(importing = ImportProgress(0, uris.size)) }
        val analyzed = mutableListOf<AnalyzedMedia>()
        val failures = mutableListOf<MediaImportException>()
        uris.forEachIndexed { index, uri ->
            try {
                val media = analyzer.analyze(uri)
                when {
                    media.kind == MediaKind.AUDIO ->
                        failures += MediaImportException(MediaImportException.Reason.UNSUPPORTED_TYPE, media.displayName)
                    media.info.durationUs <= 0 ->
                        failures += MediaImportException(MediaImportException.Reason.CORRUPT, media.displayName)
                    else -> analyzed += media
                }
            } catch (e: MediaImportException) {
                failures += e
            }
            _uiState.update { it.copy(importing = ImportProgress(index + 1, uris.size)) }
        }
        _uiState.update { it.copy(importing = null) }
        if (failures.isNotEmpty()) _messages.send(EditorMessage.ImportFailed(failures))
        return analyzed
    }

    private fun sourceOf(media: AnalyzedMedia) =
        MediaSource(uri = media.uri.toString(), kind = media.kind, info = media.info)

    /**
     * Shows [project] with any finished proxies filled in, saves it if asked, and updates the
     * preview. Callers hold [edits].
     */
    private suspend fun setProject(project: Project, save: Boolean) {
        val withProxies = withProxyPaths(project)
        val saved = if (save) withProxies.copy(modifiedAt = System.currentTimeMillis()) else withProxies
        if (save) repository.save(saved)
        val states = proxies.states.value
        _uiState.update { state ->
            val clips = MainTrackEdits.clips(saved).map { clip ->
                val info = clip.source.info
                ClipUi(
                    clip = clip,
                    needsProxy = clip.source.kind == MediaKind.VIDEO && info != null && ProxyPolicy.needsProxy(info),
                    proxy = states[clip.source.uri],
                    frameUri = proxyUri(clip) ?: clip.source.uri,
                )
            }
            state.copy(
                project = saved,
                clips = clips,
                selectedClipId = state.selectedClipId?.takeIf { id -> clips.any { it.clip.id == id } },
                canUndo = history.canUndo,
                canRedo = history.canRedo,
            )
        }
        rebuildPreview()
    }

    private fun refreshHistoryFlags() {
        _uiState.update { it.copy(canUndo = history.canUndo, canRedo = history.canRedo) }
    }

    private fun withProxyPaths(project: Project): Project {
        val states = proxies.states.value
        var changed = false
        val tracks = project.timeline.tracks.map { track ->
            track.copy(
                items = track.items.map { item ->
                    val ready = (item as? MediaClip)?.let { states[it.source.uri] as? ProxyState.Ready }
                    if (item is MediaClip && ready != null && item.source.proxyPath != ready.path) {
                        changed = true
                        item.copy(source = item.source.copy(proxyPath = ready.path))
                    } else {
                        item
                    }
                },
            )
        }
        return if (changed) project.copy(timeline = project.timeline.copy(tracks = tracks)) else project
    }

    private suspend fun onProxyStates() {
        edits.withLock {
            val project = _uiState.value.project ?: return@withLock
            val updated = withProxyPaths(project)
            setProject(updated, save = updated != project)
        }
    }

    private fun requestProxyIfNeeded(clip: MediaClip) = requestProxyIfNeeded(clip.source)

    private fun requestProxyIfNeeded(source: MediaSource) {
        val info = source.info ?: return
        if (source.kind == MediaKind.VIDEO && ProxyPolicy.needsProxy(info)) proxies.request(source.uri, info)
    }

    private fun proxyUri(clip: MediaClip): String? =
        clip.source.proxyPath?.let(::File)?.takeIf { it.isFile }?.let { Uri.fromFile(it).toString() }

    private fun rebuildPreview() {
        val state = _uiState.value
        val project = state.project ?: return
        val useProxy = state.previewSource == PreviewSource.PROXY
        val clips = state.clips.map { it.clip }
        fun uriFor(clip: MediaClip) = (if (useProxy) proxyUri(clip) else null) ?: clip.source.uri
        val key = clips.map { listOf(it.id, it.trimStartUs, it.trimEndUs, it.speed, uriFor(it)) }
        if (key == previewKey) {
            previewRebuildPending = false
            return
        }
        if (preview.isPlaying.value) {
            previewRebuildPending = true
            return
        }
        previewRebuildPending = false
        previewKey = key
        val fps = project.settings.frameRate.takeIf { it > 0f }
            ?: project.firstMediaClip?.source?.info?.frameRate?.takeIf { it > 0f } ?: 30f
        val duration = state.durationUs
        val start = preview.positionUs.coerceAtMost((duration - 1).coerceAtLeast(0L))
        preview.setComposition(CompositionFactory.mainTrack(clips, ::uriFor, fps), start)
    }

    private suspend fun makeProjectThumbnail(project: Project) {
        val first = project.firstMediaClip ?: return
        val bitmap = thumbnails.thumbnail(Uri.parse(first.source.uri), first.source.kind, first.trimStartUs, maxSizePx = 480)
            ?: return
        runCatching { repository.saveThumbnail(project, bitmap) }
    }

    private fun newId() = UUID.randomUUID().toString()

    companion object {
        const val PROJECT_ID_KEY = "projectId"
        private const val SEEK_INTERVAL_MS = 50L
        private const val FRAME_SIZE_PX = 160
    }
}
