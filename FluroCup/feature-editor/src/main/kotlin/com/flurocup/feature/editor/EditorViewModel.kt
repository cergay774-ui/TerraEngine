package com.flurocup.feature.editor

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flurocup.core.data.project.PendingImports
import com.flurocup.core.data.project.ProjectRepository
import com.flurocup.core.engine.media.AnalyzedMedia
import com.flurocup.core.engine.media.MediaAnalyzer
import com.flurocup.core.engine.media.MediaImportException
import com.flurocup.core.engine.media.ThumbnailCache
import com.flurocup.core.engine.preview.PreviewClip
import com.flurocup.core.engine.preview.PreviewPlayer
import com.flurocup.core.engine.proxy.ProxyManager
import com.flurocup.core.engine.proxy.ProxyState
import com.flurocup.core.model.AspectRatio
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project
import com.flurocup.core.model.ProxyPolicy
import com.flurocup.core.model.Timeline
import com.flurocup.core.model.Track
import com.flurocup.core.model.TrackKind
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
)

data class EditorUiState(
    val loading: Boolean = true,
    val notFound: Boolean = false,
    val project: Project? = null,
    val clips: List<ClipUi> = emptyList(),
    val importing: ImportProgress? = null,
    val previewSource: PreviewSource = PreviewSource.PROXY,
) {
    /** Width / height of the preview frame: the chosen ratio, or the first clip's. */
    val previewAspect: Float
        get() {
            val settings = project?.settings
            val ratio = settings?.aspectRatio ?: AspectRatio.ORIGINAL
            if (ratio.widthRatio > 0 && ratio.heightRatio > 0) return ratio.widthRatio.toFloat() / ratio.heightRatio
            val info = project?.firstMediaClip?.source?.info
            if (info != null && info.displayWidth > 0 && info.displayHeight > 0) {
                return info.displayWidth.toFloat() / info.displayHeight
            }
            return 9f / 16f
        }
}

sealed interface EditorMessage {
    /** Files that could not be imported, with the reason for each. */
    data class ImportFailed(val failures: List<MediaImportException>) : EditorMessage
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

    val preview = PreviewPlayer(context)

    /** Imports, proxy updates and setting changes all edit the project; one at a time, so none is lost. */
    private val edits = Mutex()

    init {
        viewModelScope.launch {
            val project = repository.load(projectId)
            if (project == null) {
                _uiState.update { it.copy(loading = false, notFound = true) }
                return@launch
            }
            setProject(project, save = false)
            _uiState.update { it.copy(loading = false) }
            mainClips(project).forEach { requestProxyIfNeeded(it) }
            val pending = pendingImports.take(projectId)
            if (pending.isNotEmpty()) import(pending.map(Uri::parse))
        }
        viewModelScope.launch {
            proxies.states.collect { onProxyStates(it) }
        }
    }

    fun import(uris: List<Uri>) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            _uiState.update { it.copy(importing = ImportProgress(0, uris.size)) }
            val analyzed = mutableListOf<AnalyzedMedia>()
            val failures = mutableListOf<MediaImportException>()
            uris.forEachIndexed { index, uri ->
                try {
                    val media = analyzer.analyze(uri)
                    if (media.kind == MediaKind.AUDIO) {
                        failures += MediaImportException(MediaImportException.Reason.UNSUPPORTED_TYPE, media.displayName)
                    } else if (media.info.durationUs <= 0) {
                        failures += MediaImportException(MediaImportException.Reason.CORRUPT, media.displayName)
                    } else {
                        analyzed += media
                    }
                } catch (e: MediaImportException) {
                    failures += e
                }
                _uiState.update { it.copy(importing = ImportProgress(index + 1, uris.size)) }
            }
            if (analyzed.isNotEmpty()) {
                val updated = edit { appendToMainTrack(it, analyzed) }
                if (updated != null) {
                    mainClips(updated).forEach { requestProxyIfNeeded(it) }
                    if (!repository.hasThumbnail(updated.id)) makeProjectThumbnail(updated)
                }
            }
            _uiState.update { it.copy(importing = null) }
            if (failures.isNotEmpty()) _messages.send(EditorMessage.ImportFailed(failures))
        }
    }

    fun setAspectRatio(ratio: AspectRatio) {
        viewModelScope.launch {
            edit { project ->
                if (project.settings.aspectRatio == ratio) null
                else project.copy(settings = project.settings.copy(aspectRatio = ratio))
            }
        }
    }

    fun setPreviewSource(source: PreviewSource) {
        _uiState.update { it.copy(previewSource = source) }
        refreshPreview()
    }

    fun togglePlay() = preview.togglePlay()

    suspend fun clipThumbnail(clip: MediaClip): Bitmap? =
        thumbnails.thumbnail(Uri.parse(clip.source.uri), clip.source.kind, clip.trimStartUs)

    override fun onCleared() {
        preview.release()
    }

    /** Applies [change] to the current project and saves it; [change] returns null for "no change". */
    private suspend fun edit(change: (Project) -> Project?): Project? = edits.withLock {
        val current = _uiState.value.project ?: return@withLock null
        val updated = change(current) ?: return@withLock null
        setProject(updated, save = true)
        _uiState.value.project
    }

    private suspend fun setProject(project: Project, save: Boolean) {
        val saved = if (save) project.copy(modifiedAt = System.currentTimeMillis()) else project
        if (save) repository.save(saved)
        val states = proxies.states.value
        _uiState.update { state ->
            state.copy(
                project = saved,
                clips = mainClips(saved).map { clip ->
                    val info = clip.source.info
                    ClipUi(
                        clip = clip,
                        needsProxy = clip.source.kind == MediaKind.VIDEO && info != null && ProxyPolicy.needsProxy(info),
                        proxy = states[clip.source.uri],
                    )
                },
            )
        }
        refreshPreview()
    }

    private fun appendToMainTrack(project: Project, media: List<AnalyzedMedia>): Project {
        val main = project.timeline.mainTrack ?: Track(Timeline.MAIN_TRACK_ID, TrackKind.MAIN)
        var start = main.endUs
        val newClips = media.map { m ->
            MediaClip(
                id = UUID.randomUUID().toString(),
                startUs = start,
                source = MediaSource(uri = m.uri.toString(), kind = m.kind, info = m.info),
                trimStartUs = 0L,
                trimEndUs = m.info.durationUs,
            ).also { start = it.endUs }
        }
        val updatedMain = main.copy(items = main.items + newClips)
        val others = project.timeline.tracks.filter { it.kind != TrackKind.MAIN }
        return project.copy(timeline = project.timeline.copy(tracks = listOf(updatedMain) + others))
    }

    private fun requestProxyIfNeeded(clip: MediaClip) {
        val info = clip.source.info ?: return
        if (clip.source.kind == MediaKind.VIDEO && ProxyPolicy.needsProxy(info)) proxies.request(clip.source.uri, info)
    }

    /** Records finished proxies in the project and switches the preview to them. */
    private suspend fun onProxyStates(states: Map<String, ProxyState>) {
        _uiState.update { s -> s.copy(clips = s.clips.map { it.copy(proxy = states[it.clip.source.uri]) }) }
        edit { project ->
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
            if (changed) project.copy(timeline = project.timeline.copy(tracks = tracks)) else null
        }
    }

    private fun refreshPreview() {
        val state = _uiState.value
        val useProxy = state.previewSource == PreviewSource.PROXY
        preview.setClips(
            state.clips.map { ui ->
                val clip = ui.clip
                val proxy = clip.source.proxyPath?.takeIf { useProxy && File(it).isFile }
                PreviewClip(
                    id = clip.id,
                    uri = proxy?.let { Uri.fromFile(File(it)).toString() } ?: clip.source.uri,
                    isImage = clip.source.kind == MediaKind.IMAGE,
                    trimStartUs = clip.trimStartUs,
                    trimEndUs = clip.trimEndUs,
                )
            },
        )
    }

    private suspend fun makeProjectThumbnail(project: Project) {
        val first = project.firstMediaClip ?: return
        val bitmap = thumbnails.thumbnail(Uri.parse(first.source.uri), first.source.kind, first.trimStartUs, maxSizePx = 480)
            ?: return
        runCatching { repository.saveThumbnail(project, bitmap) }
    }

    private fun mainClips(project: Project): List<MediaClip> =
        project.timeline.mainTrack?.items?.filterIsInstance<MediaClip>()?.sortedBy { it.startUs }.orEmpty()

    companion object {
        const val PROJECT_ID_KEY = "projectId"
    }
}
