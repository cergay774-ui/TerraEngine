package com.flurocup.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Timeline(
    val tracks: List<Track> = listOf(Track(id = MAIN_TRACK_ID, kind = TrackKind.MAIN)),
) {
    val mainTrack: Track? get() = tracks.firstOrNull { it.kind == TrackKind.MAIN }

    val durationUs: Long get() = tracks.maxOfOrNull { it.endUs } ?: 0L

    companion object {
        const val MAIN_TRACK_ID = "main"
    }
}

@Serializable
enum class TrackKind { MAIN, OVERLAY, TEXT, STICKER, EFFECT, AUDIO }

@Serializable
data class Track(
    val id: String,
    val kind: TrackKind,
    val items: List<TimelineItem> = emptyList(),
    val muted: Boolean = false,
    val locked: Boolean = false,
    val hidden: Boolean = false,
) {
    val endUs: Long get() = items.maxOfOrNull { it.endUs } ?: 0L
}

/** Anything placed on a track. New item types are added as subclasses. */
@Serializable
sealed interface TimelineItem {
    val id: String
    /** Position on the timeline. */
    val startUs: Long
    /** Length on the timeline, after speed is applied. */
    val durationUs: Long

    val endUs: Long get() = startUs + durationUs
}

/** A video, photo or audio file placed on a track. */
@Serializable
@SerialName("media")
data class MediaClip(
    override val id: String,
    override val startUs: Long,
    val source: MediaSource,
    /** Trimmed range inside the source file. */
    val trimStartUs: Long = 0L,
    val trimEndUs: Long,
    val speed: Float = 1f,
    val volume: Float = 1f,
) : TimelineItem {
    override val durationUs: Long
        get() = ((trimEndUs - trimStartUs) / speed.toDouble()).toLong()
}

@Serializable
enum class MediaKind { VIDEO, IMAGE, AUDIO }

@Serializable
data class MediaSource(
    val uri: String,
    val kind: MediaKind,
    val info: MediaInfo? = null,
    /** Local proxy copy used for editing and preview; export always uses [uri]. */
    val proxyPath: String? = null,
)
