package com.flurocup.core.model.edit

import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project
import com.flurocup.core.model.Track
import com.flurocup.core.model.TrackKind
import kotlin.math.max
import kotlin.math.min

/**
 * Edits of overlay tracks. Unlike the main track, overlay clips sit at free positions; clips on
 * one track never overlap, and a track that becomes empty is removed.
 */
object OverlayEdits {

    fun overlayTracks(project: Project): List<Track> = project.timeline.overlayTracks

    /**
     * Puts [clip] at its start time on the lowest overlay track with room for it, or on a new
     * track on top.
     */
    fun add(project: Project, clip: MediaClip, newTrackId: String): Project {
        val target = overlayTracks(project).firstOrNull { fits(it, clip.startUs, clip.endUs, ignoreId = null) }
        return if (target != null) {
            replaceTrack(project, target.copy(items = sorted(target.items.filterIsInstance<MediaClip>() + clip)))
        } else {
            addTrackOnTop(project, Track(newTrackId, TrackKind.OVERLAY, listOf(clip)))
        }
    }

    /**
     * Moves a clip to [startUs] on the overlay track at [trackIndex] (0 = bottom layer). An index
     * past the top track makes a new track. Null if the clip would overlap another one there.
     */
    fun move(project: Project, clipId: String, startUs: Long, trackIndex: Int, newTrackId: String): Project? {
        val (from, clip) = project.timeline.findClip(clipId) ?: return null
        if (from.kind != TrackKind.OVERLAY) return null
        val start = max(0L, startUs)
        val moved = clip.copy(startUs = start)
        val tracks = overlayTracks(project)
        val fromIndex = tracks.indexOfFirst { it.id == from.id }
        if (trackIndex == fromIndex && start == clip.startUs) return null
        val withoutClip = replaceTrack(project, from.copy(items = from.items.filterNot { it.id == clipId }))
        return if (trackIndex !in tracks.indices) {
            removeEmptyOverlayTracks(addTrackOnTop(withoutClip, Track(newTrackId, TrackKind.OVERLAY, listOf(moved))))
        } else {
            val target = overlayTracks(withoutClip).first { it.id == tracks[trackIndex].id }
            if (!fits(target, moved.startUs, moved.endUs, ignoreId = clipId)) return null
            removeEmptyOverlayTracks(
                replaceTrack(withoutClip, target.copy(items = sorted(target.items.filterIsInstance<MediaClip>() + moved))),
            )
        }
    }

    /**
     * Trims an overlay clip: [startUs] is its new position, [trimStartUs]..[trimEndUs] the source
     * range. Kept inside the source and clear of the neighbouring clips.
     */
    fun trim(project: Project, clipId: String, startUs: Long, trimStartUs: Long, trimEndUs: Long): Project? {
        val (track, clip) = project.timeline.findClip(clipId) ?: return null
        if (track.kind != TrackKind.OVERLAY) return null
        val (lower, upper) = freeRange(track, clip)
        val (sourceStart, sourceEnd) = MainTrackEdits.clampTrim(clip, trimStartUs, trimEndUs)
        val start = startUs.coerceAtLeast(lower)
        var updated = clip.copy(startUs = start, trimStartUs = sourceStart, trimEndUs = sourceEnd)
        if (updated.endUs > upper) {
            // Shorten from the end to stay clear of the next clip.
            val allowed = upper - start
            if (allowed < MainTrackEdits.MIN_CLIP_US) return null
            updated = if (clip.source.kind == MediaKind.IMAGE) {
                updated.copy(trimStartUs = 0, trimEndUs = allowed)
            } else {
                updated.copy(trimEndUs = updated.trimStartUs + (allowed * clip.speed).toLong())
            }
        }
        if (updated == clip) return null
        val items = track.items.filterIsInstance<MediaClip>().map { if (it.id == clipId) updated else it }
        return replaceTrack(project, track.copy(items = sorted(items)))
    }

    /** Positions a clip on [track] may take without touching its neighbours: (earliest start, latest end). */
    fun freeRange(track: Track, clip: MediaClip): Pair<Long, Long> {
        val others = track.items.filterNot { it.id == clip.id }
        val lower = others.filter { it.endUs <= clip.startUs }.maxOfOrNull { it.endUs } ?: 0L
        val upper = others.filter { it.startUs >= clip.endUs }.minOfOrNull { it.startUs } ?: Long.MAX_VALUE
        return lower to upper
    }

    fun split(project: Project, clipId: String, atUs: Long, newId: String): Project? {
        val (track, clip) = project.timeline.findClip(clipId) ?: return null
        if (track.kind != TrackKind.OVERLAY) return null
        val offset = atUs - clip.startUs
        if (offset < MainTrackEdits.MIN_CLIP_US || clip.durationUs - offset < MainTrackEdits.MIN_CLIP_US) return null
        val (first, second) = if (clip.source.kind == MediaKind.IMAGE) {
            clip.copy(trimStartUs = 0, trimEndUs = offset) to
                clip.copy(id = newId, startUs = atUs, trimStartUs = 0, trimEndUs = clip.durationUs - offset)
        } else {
            val cut = clip.trimStartUs + (offset * clip.speed).toLong()
            clip.copy(trimEndUs = cut) to clip.copy(id = newId, startUs = clip.startUs + offset, trimStartUs = cut)
        }
        val items = track.items.filterIsInstance<MediaClip>().flatMap { if (it.id == clipId) listOf(first, second) else listOf(it) }
        return replaceTrack(project, track.copy(items = sorted(items)))
    }

    fun delete(project: Project, clipId: String): Project? {
        val (track, _) = project.timeline.findClip(clipId) ?: return null
        if (track.kind != TrackKind.OVERLAY) return null
        return removeEmptyOverlayTracks(replaceTrack(project, track.copy(items = track.items.filterNot { it.id == clipId })))
    }

    /** A copy right after the clip on the same track, or on a new track if there is no room. */
    fun duplicate(project: Project, clipId: String, newId: String, newTrackId: String): Project? {
        val (track, clip) = project.timeline.findClip(clipId) ?: return null
        if (track.kind != TrackKind.OVERLAY) return null
        val copy = clip.copy(id = newId, startUs = clip.endUs)
        return if (fits(track, copy.startUs, copy.endUs, ignoreId = null)) {
            replaceTrack(project, track.copy(items = sorted(track.items.filterIsInstance<MediaClip>() + copy)))
        } else {
            addTrackOnTop(project, Track(newTrackId, TrackKind.OVERLAY, listOf(copy)))
        }
    }

    /** Swaps an overlay's media, keeping its position and, where the new file allows, its length. */
    fun replace(project: Project, clipId: String, source: MediaSource): Project? {
        val (track, clip) = project.timeline.findClip(clipId) ?: return null
        if (track.kind != TrackKind.OVERLAY) return null
        val replaced = if (source.kind == MediaKind.IMAGE) {
            clip.copy(source = source, trimStartUs = 0, trimEndUs = clip.durationUs, speed = 1f)
        } else {
            val available = source.info?.durationUs?.takeIf { it > 0 } ?: clip.durationUs
            clip.copy(source = source, trimStartUs = 0, trimEndUs = min((clip.durationUs * clip.speed).toLong(), available))
        }
        return replaceTrack(project, track.copy(items = track.items.map { if (it.id == clipId) replaced else it }))
    }

    /** Moves an overlay track one layer up (+1) or down (-1). */
    fun moveTrack(project: Project, trackId: String, delta: Int): Project? {
        val tracks = project.timeline.tracks
        val overlays = tracks.filter { it.kind == TrackKind.OVERLAY }
        val from = overlays.indexOfFirst { it.id == trackId }
        val to = from + delta
        if (from < 0 || to !in overlays.indices) return null
        val reordered = overlays.toMutableList().apply { add(to, removeAt(from)) }
        return project.copy(timeline = project.timeline.copy(tracks = tracks.filter { it.kind != TrackKind.OVERLAY } + reordered))
    }

    fun removeEmptyOverlayTracks(project: Project): Project {
        val tracks = project.timeline.tracks.filterNot { it.kind == TrackKind.OVERLAY && it.items.isEmpty() }
        return project.copy(timeline = project.timeline.copy(tracks = tracks))
    }

    private fun fits(track: Track, startUs: Long, endUs: Long, ignoreId: String?): Boolean =
        track.items.none { it.id != ignoreId && it.startUs < endUs && startUs < it.endUs }

    private fun sorted(items: List<MediaClip>) = items.sortedBy { it.startUs }

    private fun replaceTrack(project: Project, track: Track): Project =
        project.copy(timeline = project.timeline.copy(tracks = project.timeline.tracks.map { if (it.id == track.id) track else it }))

    private fun addTrackOnTop(project: Project, track: Track): Project =
        project.copy(timeline = project.timeline.copy(tracks = project.timeline.tracks + track))
}

/** Edits that work on whichever track the item is on. */
object TimelineEdits {
    fun isOnMainTrack(project: Project, clipId: String): Boolean =
        project.timeline.findClip(clipId)?.first?.kind == TrackKind.MAIN

    private fun isEffect(project: Project, id: String) = EffectEdits.find(project, id) != null

    fun split(project: Project, clipId: String, atUs: Long, newId: String): Project? = when {
        isEffect(project, clipId) -> EffectEdits.split(project, clipId, atUs, newId)
        isOnMainTrack(project, clipId) -> MainTrackEdits.split(project, clipId, atUs, newId)
        else -> OverlayEdits.split(project, clipId, atUs, newId)
    }

    fun delete(project: Project, clipId: String): Project? = when {
        isEffect(project, clipId) -> EffectEdits.delete(project, clipId)
        isOnMainTrack(project, clipId) -> MainTrackEdits.delete(project, clipId)
        else -> OverlayEdits.delete(project, clipId)
    }

    fun duplicate(project: Project, clipId: String, newId: String, newTrackId: String): Project? = when {
        isEffect(project, clipId) -> EffectEdits.duplicate(project, clipId, newId, newTrackId)
        isOnMainTrack(project, clipId) -> MainTrackEdits.duplicate(project, clipId, newId)
        else -> OverlayEdits.duplicate(project, clipId, newId, newTrackId)
    }

    fun replace(project: Project, clipId: String, source: MediaSource): Project? =
        if (isOnMainTrack(project, clipId)) MainTrackEdits.replace(project, clipId, source)
        else OverlayEdits.replace(project, clipId, source)

    /** Replaces a clip with [updated] (same id), wherever it is. Null if nothing changes. */
    fun update(project: Project, updated: MediaClip): Project? {
        val (track, clip) = project.timeline.findClip(updated.id) ?: return null
        if (clip == updated) return null
        val tracks = project.timeline.tracks.map { t ->
            if (t.id == track.id) t.copy(items = t.items.map { if (it.id == updated.id) updated else it }) else t
        }
        return project.copy(timeline = project.timeline.copy(tracks = tracks))
    }
}
