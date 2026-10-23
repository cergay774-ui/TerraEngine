package com.flurocup.feature.export

import android.content.Context
import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flurocup.core.data.project.ProjectRepository
import com.flurocup.core.engine.export.EncoderSupport
import com.flurocup.core.engine.export.ExportManager
import com.flurocup.core.engine.export.ExportRequest
import com.flurocup.core.engine.export.ExportState
import com.flurocup.core.engine.export.FrameExporter
import com.flurocup.core.engine.export.MediaStoreSaver
import com.flurocup.core.model.HdrType
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.Project
import com.flurocup.core.model.edit.MainTrackEdits
import com.flurocup.core.model.export.BitrateMode
import com.flurocup.core.model.export.ExportMath
import com.flurocup.core.model.export.ExportResolution
import com.flurocup.core.model.export.ExportSettings
import com.flurocup.core.model.export.VideoCodec
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import kotlin.math.min
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class ExportUiState(
    val loading: Boolean = true,
    val project: Project? = null,
    val clips: List<MediaClip> = emptyList(),
    val aspect: Float = 16f / 9f,
    val codecs: List<VideoCodec> = emptyList(),
    val resolutions: List<ExportResolution> = emptyList(),
    val frameRates: List<Int> = emptyList(),
    val settings: ExportSettings = ExportSettings(),
    val sourceHdr: HdrType = HdrType.NONE,
    val hdrSupported: Boolean = false,
    val hasAudio: Boolean = false,
) {
    val outputSize: Pair<Int, Int> get() = ExportMath.outputSize(aspect, settings.resolution.shortSide)
    val durationUs: Long get() = project?.durationUs ?: 0L
    val estimatedBytes: Long get() = outputSize.let { (w, h) -> ExportMath.estimatedBytes(settings, w, h, durationUs) }
    val canExport: Boolean get() = !loading && durationUs > 0 && settings.resolution in resolutions
}

sealed interface ExportMessage {
    data object FrameSaved : ExportMessage
    data object FrameFailed : ExportMessage
    data object Busy : ExportMessage
}

@HiltViewModel
class ExportViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    @ApplicationContext private val context: Context,
    private val repository: ProjectRepository,
    private val encoders: EncoderSupport,
    private val exports: ExportManager,
    private val frames: FrameExporter,
    private val saver: MediaStoreSaver,
) : ViewModel() {

    private val projectId: String = checkNotNull(savedStateHandle[PROJECT_ID_KEY])
    private val positionUs: Long = savedStateHandle[POSITION_KEY] ?: 0L

    private val _uiState = MutableStateFlow(ExportUiState())
    val uiState: StateFlow<ExportUiState> = _uiState.asStateFlow()

    val exportState: StateFlow<ExportState> = exports.state

    private val _messages = Channel<ExportMessage>(Channel.BUFFERED)
    val messages: Flow<ExportMessage> = _messages.receiveAsFlow()

    val needsStoragePermission: Boolean get() = saver.needsStoragePermission

    init {
        // A result from an earlier export is not this screen's.
        exports.clearResult()
        viewModelScope.launch {
            val project = repository.load(projectId) ?: run {
                _uiState.update { it.copy(loading = false) }
                return@launch
            }
            val clips = MainTrackEdits.clips(project)
            val allClips = project.timeline.allClips
            val firstVideo = clips.firstOrNull { it.source.kind == MediaKind.VIDEO }?.source?.info
            val sourceFps = allClips.mapNotNull { it.source.info?.frameRate?.takeIf { fps -> fps > 0f } }.maxOrNull() ?: 30f
            val sourceShort = firstVideo?.let { min(it.displayWidth, it.displayHeight) } ?: 1080
            val sourceHdr = allClips.firstNotNullOfOrNull { it.source.info?.hdr?.takeIf { hdr -> hdr != HdrType.NONE } } ?: HdrType.NONE
            val frameRates = ExportMath.frameRatesUpTo(sourceFps)
            val codecs = withContext(Dispatchers.Default) { encoders.availableCodecs() }.ifEmpty { listOf(VideoCodec.H264) }
            val codec = when {
                sourceHdr != HdrType.NONE && VideoCodec.HEVC in codecs -> VideoCodec.HEVC
                VideoCodec.H264 in codecs -> VideoCodec.H264
                else -> codecs.first()
            }
            val base = ExportSettings(
                frameRate = ExportMath.nearestFrameRate(sourceFps, frameRates),
                codec = codec,
                bitrateMode = BitrateMode.RECOMMENDED,
            )
            _uiState.update {
                it.copy(
                    project = project,
                    clips = clips,
                    aspect = project.outputAspect(),
                    codecs = codecs,
                    frameRates = frameRates,
                    sourceHdr = sourceHdr,
                    hasAudio = allClips.any { clip -> clip.source.kind == MediaKind.VIDEO && (clip.source.info?.audioTrackCount ?: 1) > 0 },
                )
            }
            applySettings(base, preferredShortSide = sourceShort, keepHdrByDefault = true)
            _uiState.update { it.copy(loading = false) }
        }
    }

    fun setResolution(resolution: ExportResolution) = change { it.copy(resolution = resolution) }

    fun setFrameRate(fps: Int) = change { it.copy(frameRate = fps) }

    fun setCodec(codec: VideoCodec) = change { it.copy(codec = codec) }

    fun setBitrateMode(mode: BitrateMode) = change { it.copy(bitrateMode = mode) }

    fun setCustomBitrate(mbps: Int) = change { it.copy(customBitrateMbps = mbps.coerceIn(1, 200)) }

    fun setKeepHdr(keep: Boolean) = change { it.copy(keepHdr = keep) }

    fun exportVideo() {
        val state = _uiState.value
        val project = state.project ?: return
        if (!state.canExport) return
        val started = exports.exportVideo(ExportRequest(project, state.settings))
        if (started) ExportService.start(context) else viewModelScope.launch { _messages.send(ExportMessage.Busy) }
    }

    fun exportAudio() {
        val state = _uiState.value
        val project = state.project ?: return
        val started = exports.exportAudio(ExportRequest(project, state.settings))
        if (started) ExportService.start(context) else viewModelScope.launch { _messages.send(ExportMessage.Busy) }
    }

    fun exportFrame() {
        val state = _uiState.value
        val project = state.project ?: return
        viewModelScope.launch {
            val saved = runCatching {
                val bitmap = frames.frameAt(state.clips, positionUs) ?: error("No frame")
                saver.saveImage(bitmap, frameName(project.name))
            }.isSuccess
            _messages.send(if (saved) ExportMessage.FrameSaved else ExportMessage.FrameFailed)
        }
    }

    fun cancel() = exports.cancel()

    fun clearResult() = exports.clearResult()

    /** Uri of a finished export, for sharing. */
    val resultUri: Uri? get() = (exports.state.value as? ExportState.Done)?.uri

    private fun change(transform: (ExportSettings) -> ExportSettings) {
        viewModelScope.launch {
            val current = _uiState.value.settings
            applySettings(transform(current), preferredShortSide = current.resolution.shortSide, keepHdrByDefault = false)
        }
    }

    /**
     * Fits [requested] to what the encoder supports: resolutions that the chosen codec and frame
     * rate allow (the biggest one up to [preferredShortSide] is picked if the current one is not),
     * and HDR only where it can be kept.
     */
    private suspend fun applySettings(requested: ExportSettings, preferredShortSide: Int, keepHdrByDefault: Boolean) {
        val state = _uiState.value
        val (resolutions, hdrSupported) = withContext(Dispatchers.Default) {
            ExportResolution.entries.filter { res ->
                val (w, h) = ExportMath.outputSize(state.aspect, res.shortSide)
                encoders.supports(requested.codec, w, h, requested.frameRate)
            } to encoders.supportsHdr(requested.codec, state.sourceHdr)
        }
        val resolution = when {
            requested.resolution in resolutions && !keepHdrByDefault -> requested.resolution
            else -> resolutions.lastOrNull { it.shortSide <= preferredShortSide } ?: resolutions.firstOrNull() ?: requested.resolution
        }
        val keepHdr = hdrSupported && (if (keepHdrByDefault) true else requested.keepHdr)
        _uiState.update {
            it.copy(
                resolutions = resolutions,
                hdrSupported = hdrSupported,
                settings = requested.copy(resolution = resolution, keepHdr = keepHdr),
            )
        }
    }

    private fun frameName(projectName: String): String {
        val safe = projectName.replace(Regex("[^\\p{L}\\p{N} _-]"), "").trim().ifEmpty { "FluroCup" }
        return "${safe}_frame_" + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.ROOT).format(Date())
    }

    companion object {
        const val PROJECT_ID_KEY = "projectId"
        const val POSITION_KEY = "positionUs"
    }
}
