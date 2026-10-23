package com.flurocup.core.model.export

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OutputFrameClockTest {

    @Test
    fun thirtyToOneHundredTwentyGivesFourFramesPerInput() {
        val clock = OutputFrameClock(120f)
        assertEquals(listOf(0L), clock.plan(0))
        assertTrue(clock.restarted)
        assertEquals(listOf(8333L, 16667L, 25000L, 33333L), clock.plan(33_333))
        assertFalse(clock.restarted)
        assertEquals(listOf(41667L, 50000L, 58333L, 66667L), clock.plan(66_667))
    }

    @Test
    fun oneSecondOfThirtyFpsBecomesOneHundredTwentyFrames() {
        val clock = OutputFrameClock(120f)
        val out = (0 until 31).flatMap { clock.plan((it * 1_000_000L) / 30) }
        assertEquals(121, out.size)
        assertEquals(out.sorted(), out)
        assertEquals(out.size, out.toSet().size)
    }

    @Test
    fun oddRatesStayOnTheGrid() {
        val clock = OutputFrameClock(144f)
        val out = (0 until 25).flatMap { clock.plan((it * 1_000_000L) / 24) }
        // One second at 24 fps, 144 fps out: six frames per input.
        assertEquals(145, out.size)
        val steps = out.zipWithNext { a, b -> b - a }
        assertTrue(steps.all { it in 6944L..6945L })
    }

    @Test
    fun aJumpOrALongGapRestartsTheGrid() {
        val clock = OutputFrameClock(120f)
        clock.plan(0)
        clock.plan(33_333)
        assertEquals(listOf(2_000_000L), clock.plan(2_000_000))
        assertTrue(clock.restarted)
        assertEquals(listOf(1_000_000L), clock.plan(1_000_000))
        assertTrue(clock.restarted)
    }

    @Test
    fun inputsAlreadyAtTheTargetRatePassThrough() {
        val clock = OutputFrameClock(60f)
        val out = (0 until 61).flatMap { clock.plan((it * 1_000_000L) / 60) }
        assertEquals(61, out.size)
    }
}
