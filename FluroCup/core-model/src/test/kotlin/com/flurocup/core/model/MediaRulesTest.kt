package com.flurocup.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaRulesTest {

    private fun constant(fps: Double, count: Int) = (0 until count).map { (it * 1_000_000.0 / fps).toLong() }

    @Test
    fun constantRatesAreRecognised() {
        assertEquals(FrameRateEstimate(30f, false), FrameRateEstimator.estimate(constant(30.0, 120)))
        assertEquals(FrameRateEstimate(59.94f, false), FrameRateEstimator.estimate(constant(60_000.0 / 1001, 120)))
        assertEquals(FrameRateEstimate(23.976f, false), FrameRateEstimator.estimate(constant(24_000.0 / 1001, 120)))
    }

    @Test
    fun decodeOrderWithBFramesIsSorted() {
        val presentation = constant(25.0, 60)
        val decodeOrder = presentation.chunked(3).flatMap { if (it.size == 3) listOf(it[0], it[2], it[1]) else it }
        assertEquals(FrameRateEstimate(25f, false), FrameRateEstimator.estimate(decodeOrder))
    }

    @Test
    fun variableRateIsDetected() {
        // Alternates between 30 fps and 15 fps spacing, as phones do in low light.
        var t = 0L
        val times = (0 until 120).map { i -> t.also { t += if (i % 3 == 0) 66_666 else 33_333 } }
        val estimate = FrameRateEstimator.estimate(times)!!
        assertTrue(estimate.isVariable)
        assertEquals(22.5f, estimate.fps, 0.5f)
    }

    @Test
    fun tooFewSamples() {
        assertNull(FrameRateEstimator.estimate(listOf(0L, 33_333L)))
    }

    @Test
    fun proxyOnlyForLargeOrUndecodableSources() {
        assertTrue(ProxyPolicy.needsProxy(MediaInfo(3840, 2160)))
        assertFalse(ProxyPolicy.needsProxy(MediaInfo(1920, 1080)))
        assertFalse(ProxyPolicy.needsProxy(MediaInfo(1080, 1920)))
        assertTrue(ProxyPolicy.needsProxy(MediaInfo(1920, 1080, canDecodeInRealTime = false)))
    }

    @Test
    fun proxySizeFollowsRotationAndStaysEven() {
        assertEquals(1920 to 1080, ProxyPolicy.proxySize(MediaInfo(3840, 2160), 1080))
        assertEquals(1080 to 1920, ProxyPolicy.proxySize(MediaInfo(3840, 2160, rotationDegrees = 90), 1080))
        assertEquals(1280 to 720, ProxyPolicy.proxySize(MediaInfo(3840, 2160), 720))
        // Never upscales.
        assertEquals(1280 to 720, ProxyPolicy.proxySize(MediaInfo(1280, 720), 1080))
        // Odd results are rounded to even.
        assertEquals(1080 to 2340, ProxyPolicy.proxySize(MediaInfo(1440, 3120), 1080))
    }
}
