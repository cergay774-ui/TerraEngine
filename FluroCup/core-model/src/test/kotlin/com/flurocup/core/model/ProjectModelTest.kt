package com.flurocup.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProjectModelTest {

    private fun clip(startUs: Long, lengthUs: Long, info: MediaInfo? = null) = MediaClip(
        id = "c$startUs",
        startUs = startUs,
        source = MediaSource(uri = "content://media/$startUs", kind = MediaKind.VIDEO, info = info),
        trimEndUs = lengthUs,
    )

    @Test
    fun jsonRoundTripKeepsEverything() {
        val project = Project(
            id = "p1",
            name = "Проект 1",
            createdAt = 1L,
            modifiedAt = 2L,
            settings = ProjectSettings(aspectRatio = AspectRatio.PORTRAIT_9_16, background = Background.Blur(12f)),
            timeline = Timeline(
                listOf(
                    Track(
                        id = Timeline.MAIN_TRACK_ID,
                        kind = TrackKind.MAIN,
                        items = listOf(clip(0, 2_000_000, MediaInfo(3840, 2160, frameRate = 59.94f))),
                    ),
                ),
            ),
        )
        assertEquals(project, projectFromJson(project.toJson()))
    }

    @Test
    fun unknownFieldsFromNewerVersionsAreIgnored() {
        val json = """{"id":"p","name":"n","createdAt":0,"modifiedAt":0,"futureField":true}"""
        assertEquals("n", projectFromJson(json).name)
    }

    @Test
    fun durationIsTheEndOfTheLastItem() {
        val timeline = Timeline(
            listOf(
                Track("main", TrackKind.MAIN, listOf(clip(0, 1_000_000), clip(1_000_000, 3_000_000))),
                Track("a", TrackKind.AUDIO, listOf(clip(500_000, 1_000_000))),
            ),
        )
        assertEquals(4_000_000L, timeline.durationUs)
    }

    @Test
    fun speedShortensClipOnTimeline() {
        assertEquals(500_000L, clip(0, 1_000_000).copy(speed = 2f).durationUs)
    }

    @Test
    fun summaryUsesFirstClipAfterRotation() {
        val project = Project(
            id = "p",
            name = "n",
            createdAt = 0,
            modifiedAt = 0,
            timeline = Timeline(
                listOf(
                    Track(
                        "main",
                        TrackKind.MAIN,
                        listOf(
                            clip(5_000_000, 1_000_000, MediaInfo(1280, 720, frameRate = 30f)),
                            clip(0, 5_000_000, MediaInfo(3840, 2160, rotationDegrees = 90, frameRate = 60f)),
                        ),
                    ),
                ),
            ),
        )
        val summary = project.toSummary(null)
        assertEquals(2160, summary.sourceWidth)
        assertEquals(3840, summary.sourceHeight)
        assertEquals("4K · 60 fps", summary.formatLabel)
    }

    @Test
    fun emptyProjectHasNoFormatLabel() {
        assertNull(Project("p", "n", 0, 0).toSummary(null).formatLabel)
    }

    @Test
    fun labels() {
        assertEquals("1080p", resolutionLabel(1080, 1920))
        assertEquals("720p", resolutionLabel(1280, 720))
        assertEquals("2K", resolutionLabel(2560, 1440))
        assertEquals("8K", resolutionLabel(7680, 4320))
        assertEquals("30", frameRateLabel(29.97f))
        assertEquals("24", frameRateLabel(23.976f))
        assertEquals("12.5", frameRateLabel(12.5f))
        assertEquals("0:05", formatDuration(4_600_000))
        assertEquals("1:02:03", formatDuration(3_723_000_000))
    }
}
