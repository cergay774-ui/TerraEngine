package com.flurocup.core.engine.proxy

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.VideoEncoderSettings
import com.flurocup.core.engine.media.CodecSupport
import com.flurocup.core.engine.media.runTransformer
import com.flurocup.core.engine.media.sha1
import com.flurocup.core.model.HdrType
import com.flurocup.core.model.MediaInfo
import com.flurocup.core.model.ProxyPolicy
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

sealed interface ProxyState {
    data object Queued : ProxyState
    data class Running(val progress: Float) : ProxyState
    data class Ready(val path: String) : ProxyState
    data class Failed(val message: String?) : ProxyState
}

/**
 * Makes light H.264 proxies (1080p, or 720p on weaker decoders, same frame rate, HDR tone-mapped
 * to SDR) for sources too heavy to edit directly. Proxies are made one at a time in the background
 * and kept in internal storage; editing and preview use them, export always reads the original.
 */
@Singleton
class ProxyManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val codecSupport: CodecSupport,
) {
    private val dir = File(context.noBackupFilesDir, "proxies")
    // Transformer must be driven from a Looper thread; the main thread is the simplest one.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val queue = Channel<Request>(Channel.UNLIMITED)

    private val _states = MutableStateFlow<Map<String, ProxyState>>(emptyMap())

    /** Proxy state per source URI. */
    val states: StateFlow<Map<String, ProxyState>> = _states.asStateFlow()

    private data class Request(val sourceUri: String, val info: MediaInfo)

    init {
        scope.launch {
            for (request in queue) process(request)
        }
    }

    fun proxyFile(sourceUri: String): File = File(dir, sha1(sourceUri) + ".mp4")

    /** Queues a proxy for [sourceUri] unless one exists or is already being made. */
    fun request(sourceUri: String, info: MediaInfo) {
        val file = proxyFile(sourceUri)
        if (file.isFile) {
            setState(sourceUri, ProxyState.Ready(file.path))
            return
        }
        when (_states.value[sourceUri]) {
            ProxyState.Queued, is ProxyState.Running -> return
            else -> {
                setState(sourceUri, ProxyState.Queued)
                queue.trySend(Request(sourceUri, info))
            }
        }
    }

    private suspend fun process(request: Request) {
        val target = proxyFile(request.sourceUri)
        if (target.isFile) {
            setState(request.sourceUri, ProxyState.Ready(target.path))
            return
        }
        val partial = File(dir, target.name + ".part")
        try {
            if (!dir.isDirectory && !dir.mkdirs()) throw IOException("Cannot create $dir")
            partial.delete()
            setState(request.sourceUri, ProxyState.Running(0f))
            export(request, partial) { setState(request.sourceUri, ProxyState.Running(it)) }
            if (!partial.renameTo(target)) throw IOException("Cannot move proxy into place")
            setState(request.sourceUri, ProxyState.Ready(target.path))
        } catch (e: CancellationException) {
            partial.delete()
            throw e
        } catch (e: Exception) {
            partial.delete()
            setState(request.sourceUri, ProxyState.Failed(e.message))
        }
    }

    @OptIn(UnstableApi::class)
    private suspend fun export(request: Request, output: File, onProgress: (Float) -> Unit) {
        val info = request.info
        val shortSide = if (codecSupport.canPlayFullHdProxy(info.frameRate)) 1080 else 720
        val (width, height) = ProxyPolicy.proxySize(info, shortSide)
        val fps = if (info.frameRate > 0f) info.frameRate else 30f
        val bitrate = (width.toLong() * height * fps * BITS_PER_PIXEL).toLong().coerceIn(MIN_BITRATE, MAX_BITRATE).toInt()

        val item = EditedMediaItem.Builder(MediaItem.fromUri(request.sourceUri))
            .setEffects(Effects(emptyList(), listOf(Presentation.createForWidthAndHeight(width, height, Presentation.LAYOUT_SCALE_TO_FIT))))
            .build()
        val composition = Composition.Builder(EditedMediaItemSequence.Builder(item).build())
            .apply {
                if (info.hdr != HdrType.NONE) setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
            }
            .build()
        runTransformer(
            context = context,
            composition = composition,
            outputPath = output.path,
            configure = {
                setVideoMimeType(MimeTypes.VIDEO_H264)
                setAudioMimeType(MimeTypes.AUDIO_AAC)
                setEncoderFactory(
                    DefaultEncoderFactory.Builder(context)
                        .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
                        .setEnableFallback(true)
                        .build(),
                )
            },
            onProgress = onProgress,
        )
    }

    private fun setState(uri: String, state: ProxyState) {
        _states.update { it + (uri to state) }
    }

    private companion object {
        const val BITS_PER_PIXEL = 0.1
        const val MIN_BITRATE = 2_000_000L
        const val MAX_BITRATE = 16_000_000L
    }
}
