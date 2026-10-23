package com.flurocup.core.model.export

import kotlin.math.roundToLong

/**
 * When to emit frames for an export at a higher frame rate than the source: output frames sit
 * on an even grid of [fps] starting at the first input frame. For each input frame, [plan] gives
 * the grid times since the last emitted one, up to and including that frame's time; the ones
 * before it are made from it and the frame before (interpolated or repeated).
 *
 * A jump back in time or a gap longer than [maxGapUs] (a seek, or a missing stretch) restarts
 * the grid at that frame instead of filling the gap.
 */
class OutputFrameClock(fps: Float, private val maxGapUs: Long = 500_000L) {
    private val stepUs = 1_000_000.0 / fps
    private var originUs = UNSET
    private var lastIndex = -1L

    /** Time of the last input frame, or [UNSET] before the first. */
    var lastInputUs: Long = UNSET
        private set

    /** True if the last [plan] restarted the grid, so its frame has no frame before it to blend with. */
    var restarted: Boolean = true
        private set

    fun plan(inputUs: Long): List<Long> {
        val last = lastInputUs
        lastInputUs = inputUs
        if (last == UNSET || inputUs <= last || inputUs - last > maxGapUs) {
            originUs = inputUs
            lastIndex = 0
            restarted = true
            return listOf(inputUs)
        }
        restarted = false
        val times = ArrayList<Long>(4)
        var k = lastIndex + 1
        while (true) {
            val t = timeOf(k)
            if (t > inputUs) break
            times += t
            lastIndex = k
            k++
        }
        return times
    }

    fun reset() {
        originUs = UNSET
        lastIndex = -1
        lastInputUs = UNSET
        restarted = true
    }

    private fun timeOf(index: Long) = originUs + (index * stepUs).roundToLong()

    companion object {
        const val UNSET = Long.MIN_VALUE
    }
}
