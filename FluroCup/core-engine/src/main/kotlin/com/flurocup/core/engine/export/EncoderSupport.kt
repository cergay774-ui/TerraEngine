package com.flurocup.core.engine.export

import android.media.MediaCodecInfo
import android.os.Build
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.ColorInfo
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.EncoderUtil
import com.flurocup.core.model.HdrType
import com.flurocup.core.model.export.VideoCodec
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.max
import kotlin.math.min

/** What this phone's video encoders can do: codecs, frame sizes and rates, HDR. */
@OptIn(UnstableApi::class)
@Singleton
class EncoderSupport @Inject constructor() {

    /** Codecs with an encoder on this device, hardware ones preferred. */
    fun availableCodecs(): List<VideoCodec> = VideoCodec.entries.filter { encoders(it).isNotEmpty() }

    /**
     * True if an encoder takes [width] x [height] at [frameRate]. Transformer turns portrait frames
     * on their side for the encoder, so sizes are checked in landscape.
     */
    fun supports(codec: VideoCodec, width: Int, height: Int, frameRate: Int): Boolean {
        val w = max(width, height)
        val h = min(width, height)
        return encoders(codec).any { info ->
            runCatching {
                val video = info.getCapabilitiesForType(codec.mimeType).videoCapabilities ?: return@runCatching false
                video.isSizeSupported(w, h) && video.areSizeAndRateSupported(w, h, frameRate.toDouble())
            }.getOrDefault(false)
        }
    }

    /** True if the codec can keep this HDR format (Android 13 and newer only). */
    fun supportsHdr(codec: VideoCodec, hdr: HdrType): Boolean {
        if (Build.VERSION.SDK_INT < 33 || hdr == HdrType.NONE) return false
        val transfer = when (hdr) {
            HdrType.HLG, HdrType.DOLBY_VISION -> C.COLOR_TRANSFER_HLG
            else -> C.COLOR_TRANSFER_ST2084
        }
        val colorInfo = ColorInfo.Builder()
            .setColorSpace(C.COLOR_SPACE_BT2020)
            .setColorRange(C.COLOR_RANGE_LIMITED)
            .setColorTransfer(transfer)
            .build()
        return runCatching { EncoderUtil.getSupportedEncodersForHdrEditing(codec.mimeType, colorInfo).isNotEmpty() }
            .getOrDefault(false)
    }

    private fun encoders(codec: VideoCodec): List<MediaCodecInfo> {
        val all = runCatching { EncoderUtil.getSupportedEncoders(codec.mimeType) }.getOrDefault(emptyList())
        val hardware = all.filter { runCatching { EncoderUtil.isHardwareAccelerated(it, codec.mimeType) }.getOrDefault(false) }
        // Emulators and some budget phones only have software encoders; they still work, slowly.
        return hardware.ifEmpty { all }
    }
}
