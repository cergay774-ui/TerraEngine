package com.flurocup.feature.editor

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.SystemClock
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flurocup.core.data.project.PendingImports
import com.flurocup.core.data.project.ProjectFileStore
import com.flurocup.core.data.project.ProjectRepository
import com.flurocup.core.engine.composition.CompositionBuilder
import com.flurocup.core.engine.composition.RenderSpec
import com.flurocup.core.engine.effects.LiveLooks
import com.flurocup.core.engine.media.AnalyzedMedia
import com.flurocup.core.engine.media.MediaAnalyzer
import com.flurocup.core.engine.media.MediaImportException
import com.flurocup.core.engine.media.ThumbnailCache
import com.flurocup.core.engine.preview.PreviewEngine
import com.flurocup.core.engine.proxy.ProxyManager
import com.flurocup.core.engine.proxy.ProxyState
import com.flurocup.core.engine.segmentation.BackgroundRemover
import com.flurocup.core.model.AspectRatio
import com.flurocup.core.model.ClipLook
import com.flurocup.core.model.ClipTransform
import com.flurocup.core.model.CropRect
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaInfo
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project
import com.flurocup.core.model.ProxyPolicy
import com.flurocup.core.model.TrackKind
import com.flurocup.core.model.edit.EditCommand
import com.flurocup.core.model.edit.EditHistory
import com.flurocup.core.model.edit.MainTrackEdits
import com.flurocup.core.model.export.ExportMath
import com.flurocup.feature.editor.timeline.FrameKey
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.util.UUID
import javax.inject.Inject
import kotlin.math.min
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
    val isOverlay: Boolean,
)

/** One overlay track as the timeline shows it. */
data class OverlayTrackUi(val trackId: String, val clips: List<ClipUi>)

data class EditorUiState(
    val loading: Boolean = true,
    val notFound: Boolean = false,
    val project: Project? = null,
    val clips: List<ClipUi> = emptyList(),
    /** Overlay tracks from the top layer down, the way the timeline lists them. */
    val overlays: List<OverlayTrackUi> = emptyList(),
    val importing: ImportProgress? = null,
    val previewSource: PreviewSource = PreviewSource.PROXY,
    val selectedClipId: String? = null,
    val canUndo: Boolean = false,
    val canRedo: Boolean = false,
    val removingBackground: Boolean = false,
) {
    val selectedClip: ClipUi? get() = selectedClipId?.let { id -> allClips.firstOrNull { it.clip.id == id } }

    val allClips: List<ClipUi> get() = clips + overlays.flatMap { it.clips }

    val durationUs: Long get() = project?.durationUs ?: 0L

    /** Width / height of the preview frame, the same as the exported frame. */
    val previewAspect: Float get() = project?.outputAspect() ?: (9f / 16f)

    /** Track of the selected overlay, for moving it a layer up or down. */
    val selectedOverlayTrackIndex: Int?
        get() {
            val id = selectedClipId ?: return null
            val index = overlays.indexOfFirst { track -> track.clips.any { it.clip.id == id } }
            return index.takeIf { it >= 0 }
        }
}

sealed interface EditorMessage {
    /** Files that could not be imported, with the reason for each. */
    data class ImportFailed(val failures: List<MediaImportException>) : EditorMessage

    /** The playhead is not inside a clip, or too close to its edge, to split there. */
    data object CannotSplit : EditorMessage

    /** The overlay can't go there: another clip is in the way. */
    data object NoRoom : EditorMessage

    data object NoPersonFound : EditorMessage
}

@HiltViewModel
class EditorViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    @ApplicationContext context: Context,
    private val repository: ProjectRepository,
    private val files: ProjectFileStore,
    private val pendingImports: PendingImports,
    private val analyzer: MediaAnalyzer,
    private val proxies: ProxyManager,
    private val thumbnails: ThumbnailCache,
    private val compositions: CompositionBuilder,
    private val backgroundRemover: BackgroundRemover,
) : ViewModel() {

    /** Navigation puts the route's `projectId` argument into the saved state. */
    private val projectId: String = checkNotNull(savedStateHandle[PROJECT_ID_KEY])

    private val _uiState = MutableStateFlow(EditorUiState())
    val uiState: StateFlow<EditorUiState> = _uiState.asStateFlow()

    private val _messages = Channel<EditorMessage>(Channel.BUFFERED)
    val messages: Flow<EditorMessage> = _messages.receiveAsFlow()

    val preview = PreviewEngine(context)

    /** Looks the preview reads every frame; gestures and sliders write here before saving. */
    private val looks = LiveLooks()

    private val history = EditHistory()

    /** Edits, undo and proxy updates all change the project; one at a time, so none is lost. */
    private val edits = Mutex()

    /** What the preview currently plays, to skip rebuilding it when nothing it shows changed. */
    private var previewKey: List<Any?>? = null
    private var previewRebuildPending = false
    private var lastSeekAt = 0L

    /** A clip whose look sheet is open: it keeps the look shader so changes show live. */
    private var lookEditingClipId: String? = null

    init {
        viewModelScope.launch {
            val project = repository.load(projectId)
            if (project == null) {
                _uiState.update { it.copy(loading = false, notFound = true) }
                return@launch
            }
            edits.withLock { setProject(project, save = false) }
            _uiState.update { it.copy(loading = false) }
            project.timeline.allClips.forEach { requestProxyIfNeeded(it.source) }
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

    /** A finger starts dragging the timeline: pause and switch the player to fast seeking. */
    fun startScrub() {
        preview.pause()
        preview.setScrubbing(true)
    }

    /** The drag ended at [timelineUs]: land exactly there and leave fast-seek mode. */
    fun endScrub(timelineUs: Long) {
        preview.setScrubbing(false)
        seekTo(timelineUs, final = true)
    }

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

    /** Splits the selected clip, or the main clip under the playhead, at [atUs]. */
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
            if (execute(EditCommand.Duplicate(id, copyId, newId()))) select(copyId)
        }
    }

    fun trim(clipId: String, trimStartUs: Long, trimEndUs: Long) {
        viewModelScope.launch { execute(EditCommand.Trim(clipId, trimStartUs, trimEndUs)) }
    }

    fun move(clipId: String, toIndex: Int) {
        viewModelScope.launch { execute(EditCommand.Move(clipId, toIndex)) }
    }

    fun trimOverlay(clipId: String, startUs: Long, trimStartUs: Long, trimEndUs: Long) {
        viewModelScope.launch { execute(EditCommand.TrimOverlay(clipId, startUs, trimStartUs, trimEndUs)) }
    }

    /** Moves an overlay in time and between layers; [trackIndex] counts from the top layer, as the timeline shows them. */
    fun moveOverlay(clipId: String, startUs: Long, trackIndex: Int) {
        val count = _uiState.value.overlays.size
        // The model counts layers from the bottom; a row above the top one means a new top layer.
        val bottomUp = if (trackIndex < 0) count else count - 1 - trackIndex
        viewModelScope.launch {
            if (!execute(EditCommand.MoveOverlay(clipId, startUs, bottomUp, newId()))) _messages.send(EditorMessage.NoRoom)
        }
    }

    /** Moves the selected overlay's layer up (towards the viewer) or down. */
    fun moveSelectedLayer(up: Boolean) {
        val state = _uiState.value
        val id = state.selectedClipId ?: return
        val trackId = state.project?.timeline?.findClip(id)?.first?.takeIf { it.kind == TrackKind.OVERLAY }?.id ?: return
        viewModelScope.launch { execute(EditCommand.MoveTrack(trackId, if (up) 1 else -1)) }
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
                clips.forEach { requestProxyIfNeeded(it.source) }
                _uiState.value.project?.let { if (!repository.hasThumbnail(it.id)) makeProjectThumbnail(it) }
            }
        }
    }

    /** Adds the picked files as overlays from [atUs], one after another. */
    fun importOverlays(uris: List<Uri>, atUs: Long) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            val media = analyzeAll(uris)
            if (media.isEmpty()) return@launch
            var start = atUs.coerceAtLeast(0L)
            val commands = media.map { m ->
                val clip = MediaClip(
                    id = newId(),
                    startUs = start,
                    source = sourceOf(m),
                    trimStartUs = 0,
                    trimEndUs = m.info.durationUs,
                    transform = ClipTransform.OVERLAY_DEFAULT,
                )
                start = clip.endUs
                EditCommand.AddOverlay(clip, newId())
            }
            if (execute(EditCommand.Batch(commands))) {
                commands.forEach { requestProxyIfNeeded(it.clip.source) }
                select(commands.last().clip.id)
            }
        }
    }

    /** Shows [look] on the clip at once, without saving (a finger or slider is still moving). */
    fun previewLook(clipId: String, look: ClipLook) {
        looks.set(clipId, look)
        preview.refresh()
    }

    /** Saves the clip's look as one undoable step. */
    fun commitLook(clipId: String, look: ClipLook) {
        val clip = _uiState.value.allClips.firstOrNull { it.clip.id == clipId }?.clip ?: return
        viewModelScope.launch {
            if (!execute(EditCommand.UpdateClip(clip.withLook(look)))) {
                // Nothing changed: put the live look back to the saved one.
                looks.set(clipId, clip.look)
                preview.refresh()
            }
        }
    }

    /** The look as the preview currently shows it, including unsaved changes. */
    fun currentLook(clipId: String): ClipLook? =
        looks.get(clipId) ?: _uiState.value.allClips.firstOrNull { it.clip.id == clipId }?.clip?.look

    fun setCrop(clipId: String, crop: CropRect) {
        val clip = _uiState.value.allClips.firstOrNull { it.clip.id == clipId }?.clip ?: return
        viewModelScope.launch { execute(EditCommand.UpdateClip(clip.copy(crop = crop.clamped()))) }
    }

    /** Keeps the look shader on [clipId] while its look is edited, so changes show live; null ends editing. */
    fun setLookEditing(clipId: String?) {
        if (lookEditingClipId == clipId) return
        lookEditingClipId = clipId
        rebuildPreview()
    }

    /** Replaces the selected photo with a cut-out of the person in it. */
    fun removeBackground() {
        val ui = _uiState.value.selectedClip ?: return
        val clip = ui.clip
        if (clip.source.kind != MediaKind.IMAGE) return
        _uiState.update { it.copy(removingBackground = true) }
        viewModelScope.launch {
            try {
                val output = File(files.projectDir(projectId), "cutouts/${newId()}.png")
                val size = runCatching { backgroundRemover.cutOut(Uri.parse(clip.source.uri), output) }.getOrNull()
                if (size == null) {
                    _messages.send(EditorMessage.NoPersonFound)
                    return@launch
                }
                val source = MediaSource(
                    uri = Uri.fromFile(output).toString(),
                    kind = MediaKind.IMAGE,
                    info = MediaInfo(size.first, size.second, durationUs = clip.durationUs),
                )
                execute(EditCommand.Replace(clip.id, source))
            } finally {
                _uiState.update { it.copy(removingBackground = false) }
            }
        }
    }

    /** The selected clip's picture under the playhead, for the chroma-key colour picker. */
    suspend fun frameForColorPick(clip: MediaClip, atUs: Long): Bitmap? {
        val offsetUs = (atUs - clip.startUs).coerceIn(0L, clip.durationUs)
        val sourceUs = if (clip.source.kind == MediaKind.IMAGE) 0L else clip.trimStartUs + (offsetUs * clip.speed).toLong()
        val uri = proxyUri(clip) ?: clip.source.uri
        return thumbnails.thumbnail(Uri.parse(uri), clip.source.kind, sourceUs, maxSizePx = 720)
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
        fun ui(clip: MediaClip, overlay: Boolean): ClipUi {
            val info = clip.source.info
            return ClipUi(
                clip = clip,
                needsProxy = clip.source.kind == MediaKind.VIDEO && info != null && ProxyPolicy.needsProxy(info),
                proxy = states[clip.source.uri],
                frameUri = proxyUri(clip) ?: clip.source.uri,
                isOverlay = overlay,
            )
        }
        val clips = MainTrackEdits.clips(saved).map { ui(it, overlay = false) }
        val overlays = saved.timeline.overlayTracks.asReversed().map { track ->
            OverlayTrackUi(track.id, track.items.filterIsInstance<MediaClip>().sortedBy { it.startUs }.map { ui(it, overlay = true) })
        }
        val allIds = (clips + overlays.flatMap { it.clips }).map { it.clip.id }.toSet()
        _uiState.update { state ->
            state.copy(
                project = saved,
                clips = clips,
                overlays = overlays,
                selectedClipId = state.selectedClipId?.takeIf { it in allIds },
                canUndo = history.canUndo,
                canRedo = history.canRedo,
            )
        }
        // Saved looks win over any live value left from a gesture (this is also how undo shows).
        var looksChanged = false
        saved.timeline.allClips.forEach { clip ->
            if (looks.get(clip.id) != clip.look) {
                looks.set(clip.id, clip.look)
                looksChanged = true
            }
        }
        looks.retainOnly(allIds)
        rebuildPreview()
        if (looksChanged) preview.refresh()
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
        fun uriFor(clip: MediaClip) = (if (useProxy) proxyUri(clip) else null) ?: clip.source.uri

        val fps = project.settings.frameRate.takeIf { it > 0f }
            ?: project.firstMediaClip?.source?.info?.frameRate?.takeIf { it > 0f } ?: 30f
        val sourceShort = project.timeline.allClips
            .mapNotNull { clip -> clip.source.info?.let { min(it.displayWidth, it.displayHeight) }?.takeIf { it > 0 } }
            .maxOrNull() ?: PREVIEW_SHORT_SIDE
        val layered = compositions.isLayered(project)
        // Mixing layers costs more per frame; 720p looks the same on a phone screen.
        val previewShort = if (layered) LAYERED_PREVIEW_SHORT_SIDE else PREVIEW_SHORT_SIDE
        val (width, height) = ExportMath.outputSize(project.outputAspect(), min(previewShort, sourceShort))
        val forced = setOfNotNull(lookEditingClipId)

        // Looks are read live, so only what changes the structure of the composition is compared.
        val key = listOf(width, height, fps, forced, project.settings.background) + project.timeline.tracks.map { track ->
            listOf(track.id, track.kind, track.hidden) + track.items.filterIsInstance<MediaClip>().map {
                listOf(it.id, it.startUs, it.trimStartUs, it.trimEndUs, it.speed, uriFor(it), it.crop, it.look.needsShader)
            }
        }
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
        val spec = RenderSpec(
            width = width,
            height = height,
            frameRate = fps,
            uriFor = ::uriFor,
            lookFor = looks::forClip,
            forceLookShader = forced,
        )
        val start = preview.positionUs.coerceAtMost((state.durationUs - 1).coerceAtLeast(0L))
        val composition = runCatching { compositions.video(project, spec) }.getOrNull()
        preview.setComposition(composition, start, layered = layered)
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
        private const val PREVIEW_SHORT_SIDE = 1080
        private const val LAYERED_PREVIEW_SHORT_SIDE = 720
    }
}
