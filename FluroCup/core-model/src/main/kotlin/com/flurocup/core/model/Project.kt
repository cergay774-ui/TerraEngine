package com.flurocup.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A FluroCup project as it is stored in its JSON file. All times are in microseconds,
 * matching Media3.
 */
@Serializable
data class Project(
    val id: String,
    val name: String,
    val createdAt: Long,
    val modifiedAt: Long,
    val settings: ProjectSettings = ProjectSettings(),
    val timeline: Timeline = Timeline(),
    val formatVersion: Int = CURRENT_FORMAT_VERSION,
) {
    val durationUs: Long get() = timeline.durationUs

    /** The first clip on the main track, which the project's defaults come from. */
    val firstMediaClip: MediaClip?
        get() = timeline.mainTrack?.items?.filterIsInstance<MediaClip>()?.minByOrNull { it.startUs }

    /** Width / height of the output frame: the chosen ratio, or the first clip's shape. */
    fun outputAspect(): Float {
        val ratio = settings.aspectRatio
        if (ratio.widthRatio > 0 && ratio.heightRatio > 0) return ratio.widthRatio.toFloat() / ratio.heightRatio
        val info = firstMediaClip?.source?.info
        if (info != null && info.displayWidth > 0 && info.displayHeight > 0) {
            return info.displayWidth.toFloat() / info.displayHeight
        }
        return 9f / 16f
    }

    fun toSummary(thumbnailPath: String?): ProjectSummary {
        val info = firstMediaClip?.source?.info
        return ProjectSummary(
            id = id,
            name = name,
            createdAt = createdAt,
            modifiedAt = modifiedAt,
            durationUs = durationUs,
            sourceWidth = info?.displayWidth,
            sourceHeight = info?.displayHeight,
            sourceFrameRate = info?.frameRate,
            thumbnailPath = thumbnailPath,
        )
    }

    companion object {
        const val CURRENT_FORMAT_VERSION = 1
    }
}

@Serializable
data class ProjectSettings(
    val aspectRatio: AspectRatio = AspectRatio.ORIGINAL,
    /** Output size; 0 means "take it from the first clip". */
    val width: Int = 0,
    val height: Int = 0,
    /** Output frame rate; 0 means "take it from the first clip". */
    val frameRate: Float = 0f,
    val background: Background = Background.Color(0xFF000000),
)

@Serializable
enum class AspectRatio(val widthRatio: Int, val heightRatio: Int) {
    ORIGINAL(0, 0),
    PORTRAIT_9_16(9, 16),
    LANDSCAPE_16_9(16, 9),
    SQUARE_1_1(1, 1),
    PORTRAIT_4_5(4, 5),
    CINEMA_21_9(21, 9),
    CLASSIC_4_3(4, 3),
    FREE(0, 0),
}

/** What fills the frame where no clip covers it. */
@Serializable
sealed interface Background {
    @Serializable
    @SerialName("color")
    data class Color(val argb: Long) : Background

    @Serializable
    @SerialName("blur")
    data class Blur(val radius: Float = 24f) : Background

    @Serializable
    @SerialName("image")
    data class Image(val uri: String) : Background
}
