package com.flurocup.core.engine.export

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.VideoEncoderSettings
import com.flurocup.core.engine.composition.CompositionFactory
import com.flurocup.core.engine.media.runTransformer
import com.flurocup.core.model.HdrType
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.export.ExportMath
import com.flurocup.core.model.export.ExportSettings
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class ExportKind { VIDEO, AUDIO }

sealed interface ExportState {
    data object Idle : ExportState

    data class Running(val kind: ExportKind, val projectName: String, val progress: Float?) : ExportState

    data class Done(val kind: ExportKind, val uri: Uri, val mimeType: String, val sizeBytes: Long) : ExportState

    /** [code] is Media3's error code name, useful in a bug report. */
    data class Failed(val kind: ExportKind, val code: String?, val message: String?) : ExportState

    data class Cancelled(val kind: ExportKind) : ExportState
}

/** What to export: the main track, always read from the original files. */
data class ExportRequest(
    val projectName: String,
    val clips: List<MediaClip>,
    val aspect: Float,
    val settings: ExportSettings,
)

/**
 * Runs one export at a time with Media3 Transformer and saves the result to the gallery. It lives
 * as long as the app process; ExportService keeps the process in the foreground meanwhile.
 */
@OptIn(UnstableApi::class)
@Singleton
class ExportManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val saver: MediaStoreSaver,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _state = MutableStateFlow<ExportState>(ExportState.Idle)
    val state: StateFlow<ExportState> = _state.asStateFlow()
    private var job: Job? = null

    val isRunning: Boolean get() = _state.value is ExportState.Running

    /** Starts a video export; false if another export is still running. */
    fun exportVideo(request: ExportRequest): Boolean = start(ExportKind.VIDEO, request.projectName) { output ->
        val settings = request.settings
        val (width, height) = ExportMath.outputSize(request.aspect, settings.resolution.shortSide)
        val sourceFps = request.clips.mapNotNull { it.source.info?.frameRate?.takeIf { fps -> fps > 0f } }.maxOrNull()
        val effects = buildList<Effect> {
            if (sourceFps != null && settings.frameRate < sourceFps - 0.5f) {
                add(FrameDropEffect.createDefaultFrameDropEffect(settings.frameRate.toFloat()))
            }
            add(Presentation.createForWidthAndHeight(width, height, Presentation.LAYOUT_SCALE_TO_FIT))
        }
        val anyHdr = request.clips.any { (it.source.info?.hdr ?: HdrType.NONE) != HdrType.NONE }
        val hasSound = request.clips.any { hasAudio(it) }
        val composition = CompositionFactory.mainTrack(
            clips = request.clips,
            uriFor = { it.source.uri },
            imageFrameRate = settings.frameRate.toFloat(),
            videoEffects = effects,
            hdrMode = if (anyHdr && !settings.keepHdr) Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL else null,
            // Silence fills photos and silent clips when other clips have sound.
            forceAudioTrack = hasSound && request.clips.any { !hasAudio(it) },
        ) ?: throw NothingToExport()
        val bitrate = ExportMath.videoBitrate(settings, width, height)
        runTransformer(
            context = context,
            composition = composition,
            outputPath = output.path,
            configure = {
                setVideoMimeType(settings.codec.mimeType)
                setAudioMimeType(MimeTypes.AUDIO_AAC)
                setEncoderFactory(
                    DefaultEncoderFactory.Builder(context)
                        .setRequestedVideoEncoderSettings(
                            if (bitrate != null) VideoEncoderSettings.Builder().setBitrate(bitrate).build() else VideoEncoderSettings.DEFAULT,
                        )
                        .setEnableFallback(true)
                        .build(),
                )
            },
            onProgress = ::onProgress,
        )
        saver.saveVideo(output, fileName(request.projectName)) to "video/mp4"
    }

    /** Starts exporting the sound only; false if another export is still running. */
    fun exportAudio(request: ExportRequest): Boolean = start(ExportKind.AUDIO, request.projectName) { output ->
        if (request.clips.none { hasAudio(it) }) throw NothingToExport()
        val composition = CompositionFactory.mainTrack(
            clips = request.clips,
            uriFor = { it.source.uri },
            audioOnly = true,
        ) ?: throw NothingToExport()
        runTransformer(
            context = context,
            composition = composition,
            outputPath = output.path,
            configure = { setAudioMimeType(MimeTypes.AUDIO_AAC) },
            onProgress = ::onProgress,
        )
        saver.saveAudio(output, fileName(request.projectName)) to "audio/mp4"
    }

    fun cancel() {
        job?.cancel()
    }

    /** Forgets a finished export, so the screen starts clean next time. */
    fun clearResult() {
        if (!isRunning) _state.value = ExportState.Idle
    }

    private fun start(kind: ExportKind, projectName: String, export: suspend (File) -> Pair<Uri, String>): Boolean {
        if (isRunning) return false
        _state.value = ExportState.Running(kind, projectName, null)
        job = scope.launch {
            val dir = File(context.cacheDir, "export").apply { mkdirs() }
            val output = File(dir, "export_${System.currentTimeMillis()}." + if (kind == ExportKind.AUDIO) "m4a" else "mp4")
            try {
                val (uri, mimeType) = export(output)
                _state.value = ExportState.Done(kind, uri, mimeType, output.length())
            } catch (e: CancellationException) {
                _state.value = ExportState.Cancelled(kind)
            } catch (e: NothingToExport) {
                _state.value = ExportState.Failed(kind, NOTHING_TO_EXPORT, null)
            } catch (e: ExportException) {
                Log.w(TAG, "Export failed", e)
                _state.value = ExportState.Failed(kind, e.errorCodeName, e.cause?.message ?: e.message)
            } catch (e: Exception) {
                Log.w(TAG, "Export failed", e)
                _state.value = ExportState.Failed(kind, e.javaClass.simpleName, e.message)
            } finally {
                output.delete()
            }
        }
        return true
    }

    private fun onProgress(progress: Float) {
        val current = _state.value
        if (current is ExportState.Running) _state.value = current.copy(progress = progress)
    }

    private fun hasAudio(clip: MediaClip): Boolean =
        clip.source.kind == MediaKind.VIDEO && (clip.source.info?.audioTrackCount ?: 1) > 0

    private fun fileName(projectName: String): String {
        val safe = projectName.replace(Regex("[^\\p{L}\\p{N} _-]"), "").trim().ifEmpty { "FluroCup" }
        return "${safe}_" + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.ROOT).format(Date())
    }

    private class NothingToExport : Exception()

    companion object {
        /** [ExportState.Failed.code] when the project has nothing to export. */
        const val NOTHING_TO_EXPORT = "NOTHING_TO_EXPORT"
        private const val TAG = "ExportManager"
    }
}
