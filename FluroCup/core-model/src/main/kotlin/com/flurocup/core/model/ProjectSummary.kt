package com.flurocup.core.model

import java.util.Locale
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt

/** What the project list needs to show a card, without loading the whole project. */
data class ProjectSummary(
    val id: String,
    val name: String,
    val createdAt: Long,
    val modifiedAt: Long,
    val durationUs: Long,
    val sourceWidth: Int?,
    val sourceHeight: Int?,
    val sourceFrameRate: Float?,
    val thumbnailPath: String?,
) {
    /** For example "4K · 60 fps", or null for a project without clips. */
    val formatLabel: String?
        get() {
            val w = sourceWidth ?: return null
            val h = sourceHeight ?: return null
            if (w <= 0 || h <= 0) return null
            val resolution = resolutionLabel(w, h)
            val fps = sourceFrameRate?.takeIf { it > 0f } ?: return resolution
            return "$resolution · ${frameRateLabel(fps)} fps"
        }
}

/** Names a resolution by its short side, the way editors and phones do. */
fun resolutionLabel(width: Int, height: Int): String {
    val shortSide = min(width, height)
    return when {
        shortSide >= 4320 -> "8K"
        shortSide >= 2160 -> "4K"
        shortSide >= 1440 -> "2K"
        else -> "${shortSide}p"
    }
}

/** 29.97 shows as "30", 23.976 as "24"; exact fractional rates such as 12.5 keep one decimal. */
fun frameRateLabel(fps: Float): String {
    val rounded = fps.roundToInt()
    if (abs(fps - rounded) < 0.05f || abs(fps - rounded * 1000f / 1001f) < 0.01f) return rounded.toString()
    return ((fps * 10).roundToInt() / 10f).toString()
}

/** "0:05", "12:34", "1:02:03". */
fun formatDuration(durationUs: Long): String {
    val totalSeconds = (durationUs.coerceAtLeast(0L) + 500_000L) / 1_000_000L
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.ROOT, "%d:%02d", minutes, seconds)
    }
}
