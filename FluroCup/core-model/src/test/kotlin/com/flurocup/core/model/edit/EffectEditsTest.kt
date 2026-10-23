package com.flurocup.core.model.edit

import com.flurocup.core.model.EffectItem
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaInfo
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project
import com.flurocup.core.model.projectFromJson
import com.flurocup.core.model.toJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EffectEditsTest {

    private val base = MainTrackEdits.withClips(
        Project("p", "n", 0, 0),
        listOf(MediaClip("main", 0, MediaSource("content://m", MediaKind.VIDEO, MediaInfo(1280, 720, durationUs = 10_000_000)), trimEndUs = 10_000_000)),
    )

    private fun fx(id: String, startUs: Long, lengthUs: Long = 2_000_000) = EffectItem(id, startUs, lengthUs, "vhs")

    private fun Project.effectLayout() = timeline.effectTracks.map { track -> track.items.map { it.id to it.startUs } }

    @Test
    fun overlappingEffectsStack() {
        var p = EffectEdits.add(base, fx("a", 0), "t1")
        p = EffectEdits.add(p, fx("b", 1_000_000), "t2")
        p = EffectEdits.add(p, fx("c", 2_500_000), "t3")
        assertEquals(listOf(listOf("a" to 0L, "c" to 2_500_000L), listOf("b" to 1_000_000L)), p.effectLayout())
    }

    @Test
    fun effectsPastTheEndDontLengthenTheProject() {
        val p = EffectEdits.add(base, fx("a", 9_000_000, 5_000_000), "t1")
        assertEquals(10_000_000L, p.durationUs)
    }

    @Test
    fun moveDownAndDropTheEmptyTrack() {
        var p = EffectEdits.add(base, fx("a", 0), "t1")
        p = EffectEdits.add(p, fx("b", 1_000_000), "t2")
        p = EffectEdits.move(p, "b", 3_000_000, trackIndex = 0, newTrackId = "t3")!!
        assertEquals(listOf(listOf("a" to 0L, "b" to 3_000_000L)), p.effectLayout())
        assertNull(EffectEdits.move(p, "b", 1_000_000, trackIndex = 0, newTrackId = "t4"))
    }

    @Test
    fun trimStopsAtNeighbours() {
        var p = EffectEdits.add(base, fx("a", 0), "t1")
        p = EffectEdits.add(p, fx("b", 3_000_000), "t2")
        p = EffectEdits.trim(p, "a", 0, 5_000_000)!!
        assertEquals(3_000_000L, EffectEdits.find(p, "a")!!.second.durationUs)
        assertNull(EffectEdits.trim(p, "a", 0, 10_000))
    }

    @Test
    fun splitDuplicateDeleteThroughTimelineEdits() {
        var p = EffectEdits.add(base, fx("a", 0), "t1")
        p = TimelineEdits.split(p, "a", 1_000_000, "a2")!!
        assertEquals(listOf(listOf("a" to 0L, "a2" to 1_000_000L)), p.effectLayout())
        p = TimelineEdits.duplicate(p, "a2", "a3", "t2")!!
        assertEquals(listOf(listOf("a" to 0L, "a2" to 1_000_000L, "a3" to 2_000_000L)), p.effectLayout())
        p = TimelineEdits.delete(p, "a")!!
        p = TimelineEdits.delete(p, "a2")!!
        p = TimelineEdits.delete(p, "a3")!!
        assertEquals(emptyList<Any>(), p.timeline.effectTracks)
        assertEquals(base, p)
    }

    @Test
    fun paramsAndClipEffectsSurviveJson() {
        var p = EffectEdits.add(base, fx("a", 0).copy(params = mapOf("intensity" to 0.3f)), "t1")
        p = TimelineEdits.update(p, p.timeline.findClip("main")!!.second.copy(effects = listOf(com.flurocup.core.model.ClipEffect("e1", "blur", mapOf("radius" to 4f)))))!!
        assertEquals(p, projectFromJson(p.toJson()))
    }
}
