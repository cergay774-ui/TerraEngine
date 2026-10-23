package com.flurocup.core.model.edit

import com.flurocup.core.model.ClipTransform
import com.flurocup.core.model.CropRect
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaInfo
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project
import com.flurocup.core.model.TrackKind
import com.flurocup.core.model.projectFromJson
import com.flurocup.core.model.toJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OverlayEditsTest {

    private fun clip(id: String, startUs: Long, lengthUs: Long, sourceUs: Long = 10_000_000) = MediaClip(
        id = id,
        startUs = startUs,
        source = MediaSource("content://$id", MediaKind.VIDEO, MediaInfo(1280, 720, durationUs = sourceUs)),
        trimEndUs = lengthUs,
        transform = ClipTransform.OVERLAY_DEFAULT,
    )

    private val base = MainTrackEdits.withClips(Project("p", "n", 0, 0), listOf(clip("main", 0, 10_000_000).copy(transform = ClipTransform())))

    private fun Project.overlayLayout() = timeline.overlayTracks.map { track -> track.items.map { it.id to it.startUs } }

    @Test
    fun overlaysShareATrackWhenTheyFit() {
        var p = OverlayEdits.add(base, clip("a", 0, 2_000_000), "t1")
        p = OverlayEdits.add(p, clip("b", 3_000_000, 2_000_000), "t2")
        assertEquals(listOf(listOf("a" to 0L, "b" to 3_000_000L)), p.overlayLayout())
    }

    @Test
    fun overlappingOverlayGoesOnANewTrackOnTop() {
        var p = OverlayEdits.add(base, clip("a", 0, 2_000_000), "t1")
        p = OverlayEdits.add(p, clip("b", 1_000_000, 2_000_000), "t2")
        assertEquals(listOf(listOf("a" to 0L), listOf("b" to 1_000_000L)), p.overlayLayout())
        assertEquals(listOf("t1", "t2"), p.timeline.overlayTracks.map { it.id })
    }

    @Test
    fun moveAcrossTracksAndRemoveTheEmptyOne() {
        var p = OverlayEdits.add(base, clip("a", 0, 2_000_000), "t1")
        p = OverlayEdits.add(p, clip("b", 1_000_000, 2_000_000), "t2")
        // b to the bottom track after a: fits.
        p = OverlayEdits.move(p, "b", 2_500_000, trackIndex = 0, newTrackId = "t3")!!
        assertEquals(listOf(listOf("a" to 0L, "b" to 2_500_000L)), p.overlayLayout())
    }

    @Test
    fun moveIntoAnOccupiedSpotIsRefused() {
        var p = OverlayEdits.add(base, clip("a", 0, 2_000_000), "t1")
        p = OverlayEdits.add(p, clip("b", 1_000_000, 2_000_000), "t2")
        assertNull(OverlayEdits.move(p, "b", 500_000, trackIndex = 0, newTrackId = "t3"))
    }

    @Test
    fun moveAboveTheTopMakesANewTrack() {
        val p = OverlayEdits.move(OverlayEdits.add(base, clip("a", 0, 2_000_000), "t1"), "a", 0, trackIndex = 1, newTrackId = "t2")
        // The old track emptied and was removed, so a is alone on the new one.
        assertEquals(listOf("t2"), p!!.timeline.overlayTracks.map { it.id })
    }

    @Test
    fun trimStaysClearOfTheNextClip() {
        var p = OverlayEdits.add(base, clip("a", 0, 2_000_000), "t1")
        p = OverlayEdits.add(p, clip("b", 3_000_000, 2_000_000), "t2")
        p = OverlayEdits.trim(p, "a", 0, 0, 5_000_000)!!
        val a = p.timeline.findClip("a")!!.second
        assertEquals(3_000_000L, a.endUs)
    }

    @Test
    fun trimStartMovesTheClip() {
        val p = OverlayEdits.trim(OverlayEdits.add(base, clip("a", 1_000_000, 2_000_000), "t1"), "a", 1_500_000, 500_000, 2_000_000)!!
        val a = p.timeline.findClip("a")!!.second
        assertEquals(1_500_000L to 1_500_000L, a.startUs to a.durationUs)
    }

    @Test
    fun splitDeleteAndDuplicateWorkOnOverlays() {
        var p = OverlayEdits.add(base, clip("a", 1_000_000, 4_000_000), "t1")
        p = TimelineEdits.split(p, "a", 3_000_000, "a2")!!
        assertEquals(listOf(listOf("a" to 1_000_000L, "a2" to 3_000_000L)), p.overlayLayout())
        assertEquals(2_000_000L, p.timeline.findClip("a2")!!.second.trimStartUs)
        p = TimelineEdits.duplicate(p, "a2", "a3", "t2")!!
        assertEquals(listOf(listOf("a" to 1_000_000L, "a2" to 3_000_000L, "a3" to 5_000_000L)), p.overlayLayout())
        p = TimelineEdits.delete(p, "a")!!
        p = TimelineEdits.delete(p, "a2")!!
        p = TimelineEdits.delete(p, "a3")!!
        assertTrue(p.timeline.overlayTracks.isEmpty())
        // The main track is never touched by overlay edits.
        assertEquals(listOf("main"), MainTrackEdits.clips(p).map { it.id })
    }

    @Test
    fun trackOrderChanges() {
        var p = OverlayEdits.add(base, clip("a", 0, 2_000_000), "t1")
        p = OverlayEdits.add(p, clip("b", 0, 2_000_000), "t2")
        p = OverlayEdits.moveTrack(p, "t2", -1)!!
        assertEquals(listOf("t2", "t1"), p.timeline.overlayTracks.map { it.id })
        assertNull(OverlayEdits.moveTrack(p, "t2", -1))
        assertEquals(TrackKind.MAIN, p.timeline.tracks.first().kind)
    }

    @Test
    fun updateChangesOnlyThatClip() {
        val p = OverlayEdits.add(base, clip("a", 0, 2_000_000), "t1")
        val a = p.timeline.findClip("a")!!.second
        val updated = TimelineEdits.update(p, a.copy(opacity = 0.5f, crop = CropRect(left = 0.1f)))!!
        assertEquals(0.5f, updated.timeline.findClip("a")!!.second.opacity)
        assertNull(TimelineEdits.update(updated, updated.timeline.findClip("a")!!.second))
    }

    @Test
    fun oldProjectFilesStillLoad() {
        // A stage-3 clip has none of the look fields.
        val json = """{"id":"p","name":"n","createdAt":0,"modifiedAt":0,"timeline":{"tracks":[{"id":"main","kind":"MAIN","items":[
            {"type":"media","id":"c","startUs":0,"source":{"uri":"content://c","kind":"VIDEO"},"trimEndUs":1000000}]}]}}"""
        val clip = MainTrackEdits.clips(projectFromJson(json)).single()
        assertEquals(1f, clip.transform.scale)
        assertEquals(1f, clip.opacity)
        assertNull(clip.mask)
        val p = OverlayEdits.add(base, clip("a", 0, 2_000_000), "t1")
        assertNotNull(projectFromJson(p.toJson()).timeline.findClip("a"))
    }

    @Test
    fun cropIsClamped() {
        assertEquals(CropRect(0.45f, 0f, 0.45f, 0f), CropRect(left = 0.6f, right = 0.6f).clamped())
    }
}
