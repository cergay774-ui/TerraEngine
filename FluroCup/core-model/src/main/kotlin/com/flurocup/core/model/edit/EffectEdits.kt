package com.flurocup.core.model.edit

import com.flurocup.core.model.Project
import com.flurocup.core.model.Track
import com.flurocup.core.model.TrackKind
import com.flurocup.core.model.EffectItem
import kotlin.math.max

/** Edits of effect tracks. Like overlays: free positions, no overlaps on one track, empty tracks go away. */
object EffectEdits {

    fun tracks(project: Project): List<Track> = project.timeline.tracks.filter { it.kind == TrackKind.EFFECT }

    fun find(project: Project, id: String): Pair<Track, EffectItem>? {
        for (track in tracks(project)) {
            val item = track.items.firstOrNull { it.id == id } as? EffectItem
            if (item != null) return track to item
        }
        return null
    }

    fun add(project: Project, item: EffectItem, newTrackId: String): Project {
        val target = tracks(project).firstOrNull { fits(it, item.startUs, item.endUs, null) }
        return if (target != null) {
            replaceTrack(project, target.copy(items = sorted(target.items + item)))
        } else {
            addTrack(project, Track(newTrackId, TrackKind.EFFECT, listOf(item)))
        }
    }

    /** Moves an effect to [startUs] on the effect track at [trackIndex] (0 = bottom); past the top makes a new track. */
    fun move(project: Project, id: String, startUs: Long, trackIndex: Int, newTrackId: String): Project? {
        val (from, item) = find(project, id) ?: return null
        val moved = item.copy(startUs = max(0L, startUs))
        val all = tracks(project)
        val fromIndex = all.indexOfFirst { it.id == from.id }
        if (trackIndex == fromIndex && moved.startUs == item.startUs) return null
        val without = replaceTrack(project, from.copy(items = from.items.filterNot { it.id == id }))
        return if (trackIndex !in all.indices) {
            removeEmptyTracks(addTrack(without, Track(newTrackId, TrackKind.EFFECT, listOf(moved))))
        } else {
            val target = tracks(without).first { it.id == all[trackIndex].id }
            if (!fits(target, moved.startUs, moved.endUs, id)) return null
            removeEmptyTracks(replaceTrack(without, target.copy(items = sorted(target.items + moved))))
        }
    }

    /** Sets an effect's start and length, kept at least [MainTrackEdits.MIN_CLIP_US] and clear of its neighbours. */
    fun trim(project: Project, id: String, startUs: Long, durationUs: Long): Project? {
        val (track, item) = find(project, id) ?: return null
        val others = track.items.filterNot { it.id == id }
        val lower = others.filter { it.endUs <= item.startUs }.maxOfOrNull { it.endUs } ?: 0L
        val upper = others.filter { it.startUs >= item.endUs }.minOfOrNull { it.startUs } ?: Long.MAX_VALUE
        val start = startUs.coerceAtLeast(lower)
        val end = (start + durationUs).coerceAtMost(upper)
        if (end - start < MainTrackEdits.MIN_CLIP_US) return null
        val updated = item.copy(startUs = start, durationUs = end - start)
        if (updated == item) return null
        return replaceTrack(project, track.copy(items = sorted(track.items.map { if (it.id == id) updated else it })))
    }

    fun split(project: Project, id: String, atUs: Long, newId: String): Project? {
        val (track, item) = find(project, id) ?: return null
        val offset = atUs - item.startUs
        if (offset < MainTrackEdits.MIN_CLIP_US || item.durationUs - offset < MainTrackEdits.MIN_CLIP_US) return null
        val first = item.copy(durationUs = offset)
        val second = item.copy(id = newId, startUs = atUs, durationUs = item.durationUs - offset)
        return replaceTrack(project, track.copy(items = sorted(track.items.flatMap { if (it.id == id) listOf(first, second) else listOf(it) })))
    }

    fun delete(project: Project, id: String): Project? {
        val (track, _) = find(project, id) ?: return null
        return removeEmptyTracks(replaceTrack(project, track.copy(items = track.items.filterNot { it.id == id })))
    }

    fun duplicate(project: Project, id: String, newId: String, newTrackId: String): Project? {
        val (track, item) = find(project, id) ?: return null
        val copy = item.copy(id = newId, startUs = item.endUs)
        return if (fits(track, copy.startUs, copy.endUs, null)) {
            replaceTrack(project, track.copy(items = sorted(track.items + copy)))
        } else {
            addTrack(project, Track(newTrackId, TrackKind.EFFECT, listOf(copy)))
        }
    }

    fun update(project: Project, updated: EffectItem): Project? {
        val (track, item) = find(project, updated.id) ?: return null
        if (item == updated) return null
        return replaceTrack(project, track.copy(items = track.items.map { if (it.id == updated.id) updated else it }))
    }

    private fun fits(track: Track, startUs: Long, endUs: Long, ignoreId: String?) =
        track.items.none { it.id != ignoreId && it.startUs < endUs && startUs < it.endUs }

    private fun sorted(items: List<com.flurocup.core.model.TimelineItem>) = items.sortedBy { it.startUs }

    private fun removeEmptyTracks(project: Project) = project.copy(
        timeline = project.timeline.copy(tracks = project.timeline.tracks.filterNot { it.kind == TrackKind.EFFECT && it.items.isEmpty() }),
    )

    private fun replaceTrack(project: Project, track: Track) =
        project.copy(timeline = project.timeline.copy(tracks = project.timeline.tracks.map { if (it.id == track.id) track else it }))

    private fun addTrack(project: Project, track: Track) =
        project.copy(timeline = project.timeline.copy(tracks = project.timeline.tracks + track))
}
