package com.flurocup.core.model.export

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExportMathTest {

    @Test
    fun outputSizeFollowsTheProjectShape() {
        assertEquals(1920 to 1080, ExportMath.outputSize(16f / 9f, 1080))
        assertEquals(1080 to 1920, ExportMath.outputSize(9f / 16f, 1080))
        assertEquals(1080 to 1080, ExportMath.outputSize(1f, 1080))
        assertEquals(3840 to 2160, ExportMath.outputSize(16f / 9f, 2160))
        // 21:9 at 720p: 1680 x 720.
        assertEquals(1680 to 720, ExportMath.outputSize(21f / 9f, 720))
        // Odd sizes become even.
        assertEquals(480 to 600, ExportMath.outputSize(4f / 5f, 480))
    }

    @Test
    fun badAspectFallsBackToWidescreen() {
        assertEquals(1920 to 1080, ExportMath.outputSize(Float.NaN, 1080))
    }

    @Test
    fun bitrateScalesWithModeAndCodec() {
        val base = ExportSettings(frameRate = 30)
        val recommended = ExportMath.videoBitrate(base, 1920, 1080)!!
        assertEquals(6_220_800, recommended)
        assertTrue(ExportMath.videoBitrate(base.copy(bitrateMode = BitrateMode.LOW), 1920, 1080)!! < recommended)
        assertTrue(ExportMath.videoBitrate(base.copy(bitrateMode = BitrateMode.HIGH), 1920, 1080)!! > recommended)
        assertTrue(ExportMath.videoBitrate(base.copy(codec = VideoCodec.HEVC), 1920, 1080)!! < recommended)
        assertEquals(35_000_000, ExportMath.videoBitrate(base.copy(bitrateMode = BitrateMode.CUSTOM, customBitrateMbps = 35), 1920, 1080))
        assertNull(ExportMath.videoBitrate(base.copy(bitrateMode = BitrateMode.AUTO), 1920, 1080))
    }

    @Test
    fun sizeEstimate() {
        // 10 s at 8 Mbit/s video + 192 kbit/s audio = 10.24 MB.
        val bytes = ExportMath.estimatedBytes(
            ExportSettings(bitrateMode = BitrateMode.CUSTOM, customBitrateMbps = 8),
            1920,
            1080,
            10_000_000,
        )
        assertEquals(10_240_000L, bytes)
        assertEquals("10 МБ", formatFileSize(bytes))
        assertEquals("1,5 ГБ", formatFileSize(1_610_612_736L))
    }

    @Test
    fun frameRatesNeverExceedTheSource() {
        assertEquals(listOf(24, 25, 30), ExportMath.frameRatesUpTo(29.97f))
        assertEquals(listOf(24, 25, 30, 50, 60), ExportMath.frameRatesUpTo(59.94f))
        assertEquals(30, ExportMath.nearestFrameRate(29.97f, ExportMath.frameRatesUpTo(29.97f)))
        assertEquals(listOf(24), ExportMath.frameRatesUpTo(15f))
    }
}
