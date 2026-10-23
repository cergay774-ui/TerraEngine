package com.flurocup.core.engine.media

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.ceil

/** Answers "can this phone decode that video in real time?" from [MediaCodecList]. */
@Singleton
class CodecSupport @Inject constructor() {

    private val decoders: List<MediaCodecInfo> by lazy {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { !it.isEncoder }
    }

    /**
     * True if a hardware decoder handles [mimeType] at this size and frame rate, including the
     * stream's profile and level when [format] carries them.
     */
    fun canDecodeInRealTime(mimeType: String, width: Int, height: Int, frameRate: Float, format: MediaFormat? = null): Boolean {
        val fps = if (frameRate > 0f) frameRate.toDouble() else 30.0
        return decoders.any { info ->
            isHardware(info) && info.supportedTypes.any { it.equals(mimeType, ignoreCase = true) } &&
                runCatching { supports(info.getCapabilitiesForType(mimeType), width, height, fps, format) }
                    .getOrDefault(false)
        }
    }

    /** True if a hardware H.264 decoder plays a 1080p proxy at this rate; otherwise proxies are made at 720p. */
    fun canPlayFullHdProxy(frameRate: Float): Boolean =
        canDecodeInRealTime(MediaFormat.MIMETYPE_VIDEO_AVC, 1920, 1080, frameRate)

    private fun supports(
        caps: MediaCodecInfo.CodecCapabilities,
        width: Int,
        height: Int,
        fps: Double,
        format: MediaFormat?,
    ): Boolean {
        val video = caps.videoCapabilities ?: return false
        // Some decoders only list landscape sizes; portrait video is still decoded fine.
        val (w, h) = when {
            video.isSizeSupported(width, height) -> width to height
            video.isSizeSupported(height, width) -> height to width
            else -> return false
        }
        if (format != null && format.containsKey(MediaFormat.KEY_PROFILE)) {
            val probe = MediaFormat.createVideoFormat(caps.mimeType, w, h).apply {
                setInteger(MediaFormat.KEY_PROFILE, format.getInteger(MediaFormat.KEY_PROFILE))
                if (format.containsKey(MediaFormat.KEY_LEVEL)) setInteger(MediaFormat.KEY_LEVEL, format.getInteger(MediaFormat.KEY_LEVEL))
            }
            if (!caps.isFormatSupported(probe)) return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val points = video.supportedPerformancePoints
            if (!points.isNullOrEmpty()) {
                val needed = MediaCodecInfo.VideoCapabilities.PerformancePoint(w, h, ceil(fps).toInt())
                return points.any { it.covers(needed) }
            }
        }
        // Measured rates are the most honest figure when the vendor provides them.
        val measured = runCatching { video.getAchievableFrameRatesFor(w, h) }.getOrNull()
        if (measured != null) return measured.upper >= fps * 0.95
        return video.areSizeAndRateSupported(w, h, fps)
    }

    private fun isHardware(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return info.isHardwareAccelerated
        val name = info.name.lowercase()
        return SOFTWARE_PREFIXES.none { name.startsWith(it) } && !name.contains(".sw.")
    }

    private companion object {
        val SOFTWARE_PREFIXES = listOf("omx.google.", "c2.android.", "omx.ffmpeg.", "c2.google.")
    }
}
