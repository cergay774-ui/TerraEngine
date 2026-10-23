package com.flurocup.core.model.edit

import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project
import com.flurocup.core.model.Timeline
import com.flurocup.core.model.Track
import com.flurocup.core.model.TrackKind
import kotlin.math.max
import kotlin.math.min

/**
 * Edits of the main track. The main track is magnetic: clips always follow each other from 0
 * with no gaps, so every edit ends by laying the clips out again.
 */
object MainTrackEdits {
    /** Shortest clip an edit may leave on the timeline. */
    const val MIN_CLIP_US = 100_000L

    /** Longest a photo can be stretched to. */
    const val MAX_IMAGE_US = 60L * 60 * 1_000_000

    fun clips(project: Project): List<MediaClip> =
        project.timeline.mainTrack?.items?.filterIsInstance<MediaClip>()?.sortedBy { it.startUs }.orEmpty()

    /** Replaces the main track's clips, in this order, laid out back to back from 0. */
    fun withClips(project: Project, clips: List<MediaClip>): Project {
        var start = 0L
        val laidOut = clips.map { clip -> clip.copy(startUs = start).also { start = it.endUs } }
        val tracks = project.timeline.tracks
        val main = tracks.firstOrNull { it.kind == TrackKind.MAIN } ?: Track(Timeline.MAIN_TRACK_ID, TrackKind.MAIN)
        val updated = main.copy(items = laidOut)
        val newTracks = if (tracks.any { it.kind == TrackKind.MAIN }) {
            tracks.map { if (it.kind == TrackKind.MAIN) updated else it }
        } else {
            listOf(updated) + tracks
        }
        return project.copy(timeline = project.timeline.copy(tracks = newTracks))
    }

    fun clipAt(project: Project, timeUs: Long): MediaClip? =
        clips(project).firstOrNull { timeUs >= it.startUs && timeUs < it.endUs }

    fun append(project: Project, newClips: List<MediaClip>): Project = withClips(project, clips(project) + newClips)

    /** Cuts the clip in two at [atUs] on the timeline; null if that is too close to an edge. */
    fun split(project: Project, clipId: String, atUs: Long, newId: String): Project? {
        val list = clips(project)
        val index = list.indexOfFirst { it.id == clipId }
        if (index < 0) return null
        val clip = list[index]
        val offset = atUs - clip.startUs
        if (offset < MIN_CLIP_US || clip.durationUs - offset < MIN_CLIP_US) return null
        val (first, second) = if (clip.source.kind == MediaKind.IMAGE) {
            clip.copy(trimStartUs = 0, trimEndUs = offset) to
                clip.copy(id = newId, trimStartUs = 0, trimEndUs = clip.durationUs - offset)
        } else {
            val sourceCut = clip.trimStartUs + (offset * clip.speed).toLong()
            clip.copy(trimEndUs = sourceCut) to clip.copy(id = newId, trimStartUs = sourceCut)
        }
        return withClips(project, list.toMutableList().apply { set(index, first); add(index + 1, second) })
    }

    fun delete(project: Project, clipId: String): Project? {
        val list = clips(project)
        if (list.none { it.id == clipId }) return null
        return withClips(project, list.filterNot { it.id == clipId })
    }

    /** Inserts a copy right after the clip. */
    fun duplicate(project: Project, clipId: String, newId: String): Project? {
        val list = clips(project)
        val index = list.indexOfFirst { it.id == clipId }
        if (index < 0) return null
        return withClips(project, list.toMutableList().apply { add(index + 1, list[index].copy(id = newId)) })
    }

    /** Moves the clip to [toIndex] among the main track's clips. */
    fun move(project: Project, clipId: String, toIndex: Int): Project? {
        val list = clips(project).toMutableList()
        val from = list.indexOfFirst { it.id == clipId }
        if (from < 0) return null
        val target = toIndex.coerceIn(0, list.lastIndex)
        if (target == from) return null
        list.add(target, list.removeAt(from))
        return withClips(project, list)
    }

    /**
     * Sets the clip's source range, kept within the source and at least [MIN_CLIP_US] long.
     * Photos have no source range; for them only the resulting length matters.
     */
    fun trim(project: Project, clipId: String, trimStartUs: Long, trimEndUs: Long): Project? {
        val list = clips(project)
        val index = list.indexOfFirst { it.id == clipId }
        if (index < 0) return null
        val clip = list[index]
        val (start, end) = clampTrim(clip, trimStartUs, trimEndUs)
        if (start == clip.trimStartUs && end == clip.trimEndUs) return null
        return withClips(project, list.toMutableList().apply { set(index, clip.copy(trimStartUs = start, trimEndUs = end)) })
    }

    /** The range [trim] would actually apply; the timeline uses it to preview a drag. */
    fun clampTrim(clip: MediaClip, trimStartUs: Long, trimEndUs: Long): Pair<Long, Long> {
        val minSource = (MIN_CLIP_US * clip.speed).toLong()
        if (clip.source.kind == MediaKind.IMAGE) {
            val length = (trimEndUs - trimStartUs).coerceIn(MIN_CLIP_US, MAX_IMAGE_US)
            return 0L to length
        }
        val sourceEnd = sourceDurationUs(clip)
        val start = trimStartUs.coerceIn(0L, max(0L, min(clip.trimEndUs, sourceEnd) - minSource))
        val end = trimEndUs.coerceIn(start + minSource, max(start + minSource, sourceEnd))
        return start to end
    }

    /**
     * Swaps the clip's media and keeps its length where the new file is long enough.
     */
    fun replace(project: Project, clipId: String, source: MediaSource): Project? {
        val list = clips(project)
        val index = list.indexOfFirst { it.id == clipId }
        if (index < 0) return null
        val old = list[index]
        val replaced = if (source.kind == MediaKind.IMAGE) {
            old.copy(source = source, trimStartUs = 0, trimEndUs = old.durationUs, speed = 1f)
        } else {
            val available = source.info?.durationUs?.takeIf { it > 0 } ?: old.durationUs
            val length = min((old.durationUs * old.speed).toLong(), available).coerceAtLeast(min(MIN_CLIP_US, available))
            old.copy(source = source, trimStartUs = 0, trimEndUs = length)
        }
        return withClips(project, list.toMutableList().apply { set(index, replaced) })
    }

    /** Full length of the clip's file, or its current end if the file's length is unknown. */
    fun sourceDurationUs(clip: MediaClip): Long =
        clip.source.info?.durationUs?.takeIf { it > 0 } ?: clip.trimEndUs
}
