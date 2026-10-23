package com.flurocup.core.model.export

import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.roundToLong

enum class VideoCodec(val mimeType: String, val label: String, val bitsPerPixel: Double) {
    H264("video/avc", "H.264", 0.10),
    HEVC("video/hevc", "HEVC", 0.065),
    AV1("video/av01", "AV1", 0.05),
}

enum class BitrateMode { AUTO, LOW, RECOMMENDED, HIGH, CUSTOM }

/** Export resolutions by the short side of the frame. */
enum class ExportResolution(val shortSide: Int, val label: String) {
    SD_480(480, "480p"),
    HD_720(720, "720p"),
    FULL_HD_1080(1080, "1080p"),
    QHD_1440(1440, "2K"),
    UHD_2160(2160, "4K"),
    UHD_4320(4320, "8K"),
}

val ExportFrameRates = listOf(24, 25, 30, 50, 60, 120)

data class ExportSettings(
    val resolution: ExportResolution = ExportResolution.FULL_HD_1080,
    val frameRate: Int = 30,
    val codec: VideoCodec = VideoCodec.H264,
    val bitrateMode: BitrateMode = BitrateMode.RECOMMENDED,
    val customBitrateMbps: Int = 20,
    val keepHdr: Boolean = false,
)

/** Sizes and bitrates for an export; kept apart from the encoder so it can be tested. */
object ExportMath {
    const val AUDIO_BITRATE = 192_000

    /** Output frame for a project of [aspect] (width / height) at [shortSide], both sides even. */
    fun outputSize(aspect: Float, shortSide: Int): Pair<Int, Int> {
        val safeAspect = if (aspect.isFinite() && aspect > 0f) aspect else 16f / 9f
        return if (safeAspect >= 1f) {
            even(shortSide * safeAspect) to even(shortSide.toFloat())
        } else {
            even(shortSide.toFloat()) to even(shortSide / safeAspect)
        }
    }

    /** Video bitrate in bits per second, or null to let the encoder choose ([BitrateMode.AUTO]). */
    fun videoBitrate(settings: ExportSettings, width: Int, height: Int): Int? {
        val recommended = width.toDouble() * height * settings.frameRate * settings.codec.bitsPerPixel
        val bitrate = when (settings.bitrateMode) {
            BitrateMode.AUTO -> return null
            BitrateMode.LOW -> recommended * 0.55
            BitrateMode.RECOMMENDED -> recommended
            BitrateMode.HIGH -> recommended * 1.7
            BitrateMode.CUSTOM -> settings.customBitrateMbps * 1_000_000.0
        }
        return bitrate.coerceIn(MIN_BITRATE, MAX_BITRATE).roundToInt()
    }

    /** Expected file size; for [BitrateMode.AUTO] the recommended bitrate is assumed. */
    fun estimatedBytes(settings: ExportSettings, width: Int, height: Int, durationUs: Long): Long {
        val video = videoBitrate(settings, width, height)
            ?: videoBitrate(settings.copy(bitrateMode = BitrateMode.RECOMMENDED), width, height)!!
        val seconds = durationUs / 1_000_000.0
        return ((video + AUDIO_BITRATE) * seconds / 8).roundToLong()
    }

    /** The frame rates worth offering: up to the source's rate, since frames are dropped, never made up. */
    fun frameRatesUpTo(sourceFps: Float): List<Int> {
        val limit = if (sourceFps > 0f) sourceFps.roundToInt() else 30
        val options = ExportFrameRates.filter { it <= limit + 1 }
        return options.ifEmpty { listOf(ExportFrameRates.first()) }
    }

    /** The standard rate closest to the source's, the default choice. */
    fun nearestFrameRate(sourceFps: Float, options: List<Int>): Int {
        val target = if (sourceFps > 0f) sourceFps else 30f
        return options.minBy { kotlin.math.abs(it - target) }
    }

    private fun even(value: Float): Int = max(2, (value / 2).roundToInt() * 2)

    private const val MIN_BITRATE = 500_000.0
    private const val MAX_BITRATE = 400_000_000.0
}

/** "245 МБ", "1,2 ГБ". */
fun formatFileSize(bytes: Long, megabytes: String = "МБ", gigabytes: String = "ГБ"): String {
    val mb = bytes / (1024.0 * 1024.0)
    return if (mb >= 1024) {
        "%.1f %s".format(java.util.Locale.ROOT, mb / 1024, gigabytes).replace('.', ',')
    } else {
        "${max(1, mb.roundToInt())} $megabytes"
    }
}
