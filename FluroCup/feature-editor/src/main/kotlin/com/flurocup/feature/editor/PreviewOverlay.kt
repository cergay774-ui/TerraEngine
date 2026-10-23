package com.flurocup.feature.editor

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateRotation
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import com.flurocup.core.model.ClipLook
import com.flurocup.core.model.MediaClip
import com.flurocup.core.ui.theme.FluroColors
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * The corners of a clip on a preview of [frameWidth] x [frameHeight], clockwise from top-left,
 * matching what the engine renders: fitted to the frame, then scaled, rotated and moved.
 */
internal fun clipCorners(clip: MediaClip, look: ClipLook, frameWidth: Float, frameHeight: Float): List<Offset> {
    val info = clip.source.info
    val crop = clip.crop.clamped()
    val sourceW = (info?.displayWidth?.takeIf { it > 0 } ?: 16) * (1f - crop.left - crop.right)
    val sourceH = (info?.displayHeight?.takeIf { it > 0 } ?: 9) * (1f - crop.top - crop.bottom)
    val clipAspect = sourceW / sourceH
    val frameAspect = frameWidth / frameHeight
    val (w, h) = if (clipAspect > frameAspect) frameWidth to frameWidth / clipAspect else frameHeight * clipAspect to frameHeight
    val t = look.transform
    val halfW = w * t.scale / 2f
    val halfH = h * t.scale / 2f
    val cx = frameWidth / 2f + t.x * frameWidth
    val cy = frameHeight / 2f + t.y * frameHeight
    val angle = Math.toRadians(t.rotation.toDouble())
    val c = cos(angle).toFloat()
    val s = sin(angle).toFloat()
    return listOf(-halfW to -halfH, halfW to -halfH, halfW to halfH, -halfW to halfH).map { (dx, dy) ->
        Offset(cx + dx * c - dy * s, cy + dx * s + dy * c)
    }
}

private fun inside(point: Offset, polygon: List<Offset>): Boolean {
    var result = false
    var j = polygon.lastIndex
    for (i in polygon.indices) {
        val a = polygon[i]
        val b = polygon[j]
        if ((a.y > point.y) != (b.y > point.y) && point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
            result = !result
        }
        j = i
    }
    return result
}

/**
 * Sits over the preview. Draws a dashed frame around the selected clip; one finger moves it, two
 * fingers scale and rotate it, all shown live and saved as one undo step when the fingers lift.
 * A tap selects the topmost clip under it.
 *
 * @param clipsTopFirst clips visible at the playhead, topmost first, for tap selection; asked
 *     only on a tap, so playback doesn't recompose the screen every frame.
 */
@Composable
internal fun PreviewGestureLayer(
    selected: MediaClip?,
    clipsTopFirst: () -> List<MediaClip>,
    lookOf: (MediaClip) -> ClipLook,
    onSelect: (String?) -> Unit,
    onLookChange: (clipId: String, ClipLook) -> Unit,
    onLookCommit: (clipId: String, ClipLook) -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptics = LocalHapticFeedback.current
    var live by remember { mutableStateOf<Pair<String, ClipLook>?>(null) }
    val currentSelected by rememberUpdatedState(selected)
    val currentClips by rememberUpdatedState(clipsTopFirst)
    val currentLookOf by rememberUpdatedState(lookOf)
    val select by rememberUpdatedState(onSelect)
    val change by rememberUpdatedState(onLookChange)
    val commit by rememberUpdatedState(onLookCommit)

    Box(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val w = size.width.toFloat()
                    val h = size.height.toFloat()
                    val clip = currentSelected
                    val start = clip?.let { currentLookOf(it) }
                    var look = start
                    var moved = false
                    var lastRotationSnap = false
                    while (true) {
                        val event = awaitPointerEvent()
                        val pressed = event.changes.filter { it.pressed }
                        if (pressed.isEmpty()) break
                        val pan = event.calculatePan()
                        val zoom = event.calculateZoom()
                        val rotation = event.calculateRotation()
                        if (!moved && (abs(pan.x) + abs(pan.y) > 0.5f || zoom != 1f || rotation != 0f)) {
                            val travelled = event.changes.firstOrNull { it.id == down.id }?.let { it.position - down.position }
                            moved = pressed.size > 1 || (travelled != null && travelled.getDistance() > viewConfiguration.touchSlop)
                        }
                        if (moved && clip != null && look != null) {
                            val t = look.transform
                            var newRotation = t.rotation + rotation
                            // Light snap to straight angles, with a tick.
                            val nearest = Math.round(newRotation / 90f) * 90f
                            val snapping = pressed.size > 1 && abs(newRotation - nearest) < 3f
                            if (snapping) newRotation = nearest
                            if (snapping && !lastRotationSnap) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            lastRotationSnap = snapping
                            look = look.copy(
                                transform = t.copy(
                                    x = (t.x + pan.x / w).coerceIn(-1.5f, 1.5f),
                                    y = (t.y + pan.y / h).coerceIn(-1.5f, 1.5f),
                                    scale = (t.scale * zoom).coerceIn(0.05f, 10f),
                                    rotation = newRotation,
                                ),
                            )
                            live = clip.id to look
                            change(clip.id, look)
                            event.changes.forEach { if (it.positionChange() != Offset.Zero) it.consume() }
                        }
                    }
                    if (!moved) {
                        // A tap: select the topmost clip under the finger, or clear the selection.
                        val hit = currentClips().firstOrNull { inside(down.position, clipCorners(it, currentLookOf(it), w, h)) }
                        select(hit?.id)
                    } else if (clip != null && look != null && look != start) {
                        commit(clip.id, look)
                    }
                    live = null
                }
            },
    ) {
        val clip = selected
        if (clip != null) {
            Canvas(Modifier.fillMaxSize()) {
                val look = live?.takeIf { it.first == clip.id }?.second ?: lookOf(clip)
                val corners = clipCorners(clip, look, size.width, size.height)
                val path = Path().apply {
                    moveTo(corners[0].x, corners[0].y)
                    corners.drop(1).forEach { lineTo(it.x, it.y) }
                    close()
                }
                drawPath(path, Color.Black.copy(alpha = 0.35f), style = Stroke(width = 3.dp.toPx()))
                drawPath(
                    path,
                    FluroColors.Teal,
                    style = Stroke(width = 1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(10.dp.toPx(), 6.dp.toPx()))),
                )
                corners.forEach { drawCircle(Color.White, radius = 4.dp.toPx(), center = it) }
            }
        }
    }
}
