package com.flurocup.core.model.edit

import com.flurocup.core.model.AspectRatio
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaInfo
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MainTrackEditsTest {

    private fun video(id: String, lengthUs: Long, sourceUs: Long = lengthUs) = MediaClip(
        id = id,
        startUs = 0,
        source = MediaSource("content://$id", MediaKind.VIDEO, MediaInfo(1920, 1080, durationUs = sourceUs)),
        trimEndUs = lengthUs,
    )

    private fun photo(id: String, lengthUs: Long) = MediaClip(
        id = id,
        startUs = 0,
        source = MediaSource("content://$id", MediaKind.IMAGE, MediaInfo(4000, 3000, durationUs = 3_000_000)),
        trimEndUs = lengthUs,
    )

    private fun project(vararg clips: MediaClip) =
        MainTrackEdits.withClips(Project("p", "n", 0, 0), clips.toList())

    private fun Project.layout() = MainTrackEdits.clips(this).map { Triple(it.id, it.startUs, it.durationUs) }

    @Test
    fun clipsAreLaidOutBackToBack() {
        assertEquals(
            listOf(Triple("a", 0L, 2_000_000L), Triple("b", 2_000_000L, 1_000_000L)),
            project(video("a", 2_000_000), video("b", 1_000_000)).layout(),
        )
    }

    @Test
    fun splitCutsVideoAtTheSourcePosition() {
        val p = project(video("a", 2_000_000), video("b", 4_000_000))
        val result = MainTrackEdits.split(p, "b", 3_000_000, "b2")!!
        val clips = MainTrackEdits.clips(result)
        assertEquals(listOf("a", "b", "b2"), clips.map { it.id })
        assertEquals(0L to 1_000_000L, clips[1].trimStartUs to clips[1].trimEndUs)
        assertEquals(1_000_000L to 4_000_000L, clips[2].trimStartUs to clips[2].trimEndUs)
        assertEquals(p.durationUs, result.durationUs)
    }

    @Test
    fun splitRespectsSpeed() {
        val p = project(video("a", 4_000_000).copy(speed = 2f))
        val clips = MainTrackEdits.clips(MainTrackEdits.split(p, "a", 1_000_000, "a2")!!)
        assertEquals(2_000_000L, clips[0].trimEndUs)
        assertEquals(1_000_000L, clips[1].durationUs)
    }

    @Test
    fun splitTooCloseToAnEdgeDoesNothing() {
        val p = project(video("a", 2_000_000))
        assertNull(MainTrackEdits.split(p, "a", 50_000, "x"))
        assertNull(MainTrackEdits.split(p, "a", 1_950_000, "x"))
    }

    @Test
    fun splitPhotoKeepsBothHalvesFromTheStart() {
        val clips = MainTrackEdits.clips(MainTrackEdits.split(project(photo("a", 3_000_000)), "a", 1_000_000, "a2")!!)
        assertEquals(listOf(0L to 1_000_000L, 0L to 2_000_000L), clips.map { it.trimStartUs to it.trimEndUs })
    }

    @Test
    fun deleteClosesTheGap() {
        val p = project(video("a", 1_000_000), video("b", 1_000_000), video("c", 1_000_000))
        assertEquals(listOf(Triple("a", 0L, 1_000_000L), Triple("c", 1_000_000L, 1_000_000L)), MainTrackEdits.delete(p, "b")!!.layout())
    }

    @Test
    fun duplicateInsertsAfter() {
        val p = project(video("a", 1_000_000), video("b", 1_000_000))
        assertEquals(listOf("a", "a2", "b"), MainTrackEdits.duplicate(p, "a", "a2")!!.layout().map { it.first })
    }

    @Test
    fun moveReorders() {
        val p = project(video("a", 1_000_000), video("b", 2_000_000), video("c", 3_000_000))
        assertEquals(listOf("b", "c", "a"), MainTrackEdits.move(p, "a", 2)!!.layout().map { it.first })
        assertEquals(listOf("c", "a", "b"), MainTrackEdits.move(p, "c", 0)!!.layout().map { it.first })
        assertNull(MainTrackEdits.move(p, "b", 1))
    }

    @Test
    fun trimStaysInsideTheSource() {
        val p = project(video("a", 2_000_000, sourceUs = 5_000_000).copy(trimStartUs = 1_000_000, trimEndUs = 3_000_000))
        val clip = MainTrackEdits.clips(MainTrackEdits.trim(p, "a", -500_000, 9_000_000)!!).single()
        assertEquals(0L to 5_000_000L, clip.trimStartUs to clip.trimEndUs)
    }

    @Test
    fun trimKeepsMinimumLength() {
        val p = project(video("a", 2_000_000))
        val clip = MainTrackEdits.clips(MainTrackEdits.trim(p, "a", 1_990_000, 2_000_000)!!).single()
        assertEquals(MainTrackEdits.MIN_CLIP_US, clip.durationUs)
    }

    @Test
    fun photoCanBeStretched() {
        val clip = MainTrackEdits.clips(MainTrackEdits.trim(project(photo("a", 3_000_000)), "a", 0, 10_000_000)!!).single()
        assertEquals(10_000_000L, clip.durationUs)
    }

    @Test
    fun replaceKeepsLengthWhenPossible() {
        val p = project(video("a", 2_000_000), video("b", 1_000_000))
        val longer = MediaSource("content://new", MediaKind.VIDEO, MediaInfo(1280, 720, durationUs = 10_000_000))
        val shorter = MediaSource("content://short", MediaKind.VIDEO, MediaInfo(1280, 720, durationUs = 500_000))
        assertEquals(2_000_000L, MainTrackEdits.clips(MainTrackEdits.replace(p, "a", longer)!!)[0].durationUs)
        assertEquals(500_000L, MainTrackEdits.clips(MainTrackEdits.replace(p, "a", shorter)!!)[0].durationUs)
    }

    @Test
    fun undoRedoRestoresEveryStep() {
        val history = EditHistory()
        val start = project(video("a", 2_000_000))
        val split = history.execute(start, EditCommand.Split("a", 1_000_000, "a2"))!!
        val aspect = history.execute(split, EditCommand.SetAspectRatio(AspectRatio.SQUARE_1_1))!!
        val deleted = history.execute(aspect, EditCommand.Delete("a"))!!
        assertTrue(history.canUndo)
        assertFalse(history.canRedo)

        assertEquals(aspect, history.undo())
        assertEquals(split, history.undo())
        assertEquals(start, history.undo())
        assertNull(history.undo())

        assertEquals(split, history.redo(start))
        assertEquals(aspect, history.redo(split))
        assertEquals(deleted, history.redo(aspect))
        assertFalse(history.canRedo)
    }

    @Test
    fun newEditClearsRedo() {
        val history = EditHistory()
        val start = project(video("a", 2_000_000), video("b", 1_000_000))
        history.execute(start, EditCommand.Delete("a"))
        history.undo()
        assertTrue(history.canRedo)
        history.execute(start, EditCommand.Delete("b"))
        assertFalse(history.canRedo)
    }

    @Test
    fun noOpCommandsAreNotRecorded() {
        val history = EditHistory()
        assertNull(history.execute(project(video("a", 1_000_000)), EditCommand.Delete("missing")))
        assertFalse(history.canUndo)
    }
}
