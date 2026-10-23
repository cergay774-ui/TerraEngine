package com.flurocup.core.model

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

data class FrameRateEstimate(val fps: Float, val isVariable: Boolean)

/** Works out a video's frame rate from the presentation times of its first samples. */
object FrameRateEstimator {
    private val standardRates = floatArrayOf(
        23.976f, 24f, 25f, 29.97f, 30f, 48f, 50f, 59.94f, 60f, 90f, 100f, 119.88f, 120f, 240f,
    )

    /**
     * @param timestampsUs sample times in any order (decode order is fine, B-frames are sorted out).
     * @return null if there are too few samples to tell.
     */
    fun estimate(timestampsUs: List<Long>): FrameRateEstimate? {
        val times = timestampsUs.filter { it >= 0 }.distinct().sorted()
        if (times.size < 3) return null
        val deltas = times.zipWithNext { a, b -> b - a }
        val median = deltas.sorted()[deltas.size / 2].toDouble()
        if (median <= 0) return null
        // Constant-rate files jitter by a tick or two; variable-rate ones (most phone recordings
        // in low light) have many frames far from the typical spacing.
        val offBeat = deltas.count { abs(it - median) > median * 0.25 }
        val isVariable = offBeat > deltas.size * 0.1
        val fps = if (isVariable) {
            (times.size - 1) * 1_000_000.0 / (times.last() - times.first())
        } else {
            1_000_000.0 / median
        }
        return FrameRateEstimate(snap(fps.toFloat()), isVariable)
    }

    /** 29.968 becomes 29.97, 60.2 becomes 60; anything far from a standard rate is kept. */
    fun snap(fps: Float): Float {
        val nearest = standardRates.minBy { abs(it - fps) }
        return if (abs(nearest - fps) <= nearest * 0.01f) nearest else (fps * 100).roundToInt() / 100f
    }
}

/** When editing should switch to a lighter proxy copy, and how big that copy is. */
object ProxyPolicy {
    /** Largest short side edited directly; larger sources get a proxy. */
    const val MAX_DIRECT_SHORT_SIDE = 1080

    fun needsProxy(info: MediaInfo): Boolean =
        min(info.displayWidth, info.displayHeight) > MAX_DIRECT_SHORT_SIDE || !info.canDecodeInRealTime

    /**
     * Proxy frame size in display orientation: the short side scaled to [shortSide] (never up),
     * both sides even, as encoders require.
     */
    fun proxySize(info: MediaInfo, shortSide: Int): Pair<Int, Int> {
        val w = info.displayWidth
        val h = info.displayHeight
        val sourceShort = min(w, h)
        if (sourceShort <= 0) return 0 to 0
        val scale = min(1.0, shortSide.toDouble() / sourceShort)
        fun even(v: Double) = max(2, (v / 2).roundToInt() * 2)
        return even(w * scale) to even(h * scale)
    }
}
