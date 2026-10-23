package com.flurocup.feature.editor.timeline

import androidx.compose.animation.core.AnimationState
import androidx.compose.animation.core.DecayAnimationSpec
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDecay
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.rememberSplineBasedDecay
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.edit.MainTrackEdits
import com.flurocup.core.model.formatDuration
import com.flurocup.core.ui.theme.FluroColors
import com.flurocup.feature.editor.ClipUi
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class TrimEdge { START, END }

/** A handle drag in progress: the source range the clip would get, shown live before it is applied. */
private data class TrimDrag(
    val clipId: String,
    val edge: TrimEdge,
    val trimStartUs: Long,
    val trimEndUs: Long,
    val snapped: Boolean,
    val committed: Boolean = false,
)

/** A long-press reorder in progress. */
private data class ReorderDrag(val clipId: String, val fromIndex: Int, val startX: Float, val x: Float)

/** Where a clip is drawn, which during a trim drag differs from where the project has it. */
private data class ClipBox(val ui: ClipUi, val startUs: Long, val durationUs: Long, val trimStartUs: Long) {
    val endUs: Long get() = startUs + durationUs
}

private enum class GestureMode { TAP, SCROLL, ZOOM, LONG_PRESS, IGNORE }

private val RulerHeight = 24.dp
private val TrackTop = 30.dp
private val TrackHeight = 56.dp
private val TimelineHeight = TrackTop + TrackHeight + 10.dp
private val HandleWidth = 14.dp
private val ClipGap = 2.dp
private val SnapDistance = 12.dp
private val ReorderSize = 52.dp
private val ReorderGap = 8.dp

/**
 * The main-track timeline: playhead fixed in the middle, drag to scroll (with fling), pinch to
 * zoom, filmstrip frames on clips, tap to select, drag a selected clip's edges to trim (snapping
 * to the playhead with a haptic tick), long-press to reorder.
 */
@Composable
internal fun Timeline(
    state: TimelineState,
    clips: List<ClipUi>,
    selectedClipId: String?,
    frames: FilmstripLoader,
    onScrubStart: () -> Unit,
    onScrub: (positionUs: Long) -> Unit,
    onScrubEnd: (positionUs: Long) -> Unit,
    onSelect: (clipId: String?) -> Unit,
    onTrim: (clipId: String, trimStartUs: Long, trimEndUs: Long) -> Unit,
    onMove: (clipId: String, toIndex: Int) -> Unit,
    onAdd: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val decay = rememberSplineBasedDecay<Float>()
    val textMeasurer = rememberTextMeasurer(cacheSize = 32)
    val labelColor = MaterialTheme.colorScheme.onSurfaceVariant
    val labelStyle = remember(labelColor) { TextStyle(fontSize = 10.sp, color = labelColor) }

    var trim by remember { mutableStateOf<TrimDrag?>(null) }
    var reorder by remember { mutableStateOf<ReorderDrag?>(null) }
    val boxes = remember(clips, trim) { layoutClips(clips, trim) }

    // A committed trim keeps showing until the project catches up, so the clip doesn't jump back.
    LaunchedEffect(clips) { if (trim?.committed == true) trim = null }
    LaunchedEffect(trim?.committed) {
        if (trim?.committed == true) {
            delay(800)
            trim = null
        }
    }

    val currentBoxes by rememberUpdatedState(boxes)
    val currentClips by rememberUpdatedState(clips)
    val currentSelected by rememberUpdatedState(selectedClipId)
    val scrubStart by rememberUpdatedState(onScrubStart)
    val scrub by rememberUpdatedState(onScrub)
    val scrubEnd by rememberUpdatedState(onScrubEnd)
    val select by rememberUpdatedState(onSelect)
    val move by rememberUpdatedState(onMove)
    val fling = remember { arrayOfNulls<Job>(1) }

    val trackTopPx = with(density) { TrackTop.toPx() }
    var halfWidth by remember { mutableFloatStateOf(0f) }
    val trackHeightPx = with(density) { TrackHeight.toPx() }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(TimelineHeight)
            .onSizeChanged { halfWidth = it.width / 2f }
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    fling[0]?.cancel()
                    val alreadyHandled = down.isConsumed
                    var moved = 0f
                    val mode = if (alreadyHandled) {
                        GestureMode.IGNORE
                    } else {
                        withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                            var result = GestureMode.IGNORE
                            while (true) {
                                val event = awaitPointerEvent()
                                if (event.changes.count { it.pressed } > 1) {
                                    result = GestureMode.ZOOM
                                    break
                                }
                                val change = event.changes.firstOrNull { it.id == down.id }
                                if (change == null || change.isConsumed) {
                                    result = GestureMode.IGNORE
                                    break
                                }
                                if (!change.pressed) {
                                    result = GestureMode.TAP
                                    break
                                }
                                moved += change.positionChange().x
                                if (abs(moved) > viewConfiguration.touchSlop) {
                                    result = GestureMode.SCROLL
                                    break
                                }
                            }
                            result
                        } ?: GestureMode.LONG_PRESS
                    }

                    fun timeAt(x: Float) = state.positionUs + ((x - size.width / 2f) / state.pxPerUs).toLong()
                    fun onTrack(y: Float) = y >= trackTopPx && y <= trackTopPx + trackHeightPx

                    when (mode) {
                        GestureMode.TAP -> {
                            val position = down.position
                            if (onTrack(position.y)) {
                                val time = timeAt(position.x)
                                select(currentBoxes.firstOrNull { time >= it.startUs && time < it.endUs }?.ui?.clip?.id)
                            } else if (position.y < trackTopPx) {
                                // Tapping the ruler moves the playhead there.
                                scrubStart()
                                state.scrollToUs(timeAt(position.x))
                                scrubEnd(state.positionUs)
                            }
                        }

                        GestureMode.LONG_PRESS -> {
                            val time = timeAt(down.position.x)
                            val index = currentBoxes.indexOfFirst { time >= it.startUs && time < it.endUs }
                            if (index >= 0 && onTrack(down.position.y) && currentClips.size > 1) {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                val clipId = currentBoxes[index].ui.clip.id
                                reorder = ReorderDrag(clipId, index, down.position.x, down.position.x)
                                while (true) {
                                    val event = awaitPointerEvent()
                                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                    if (!change.pressed) break
                                    change.consume()
                                    reorder = reorder?.copy(x = change.position.x)
                                }
                                val drag = reorder
                                reorder = null
                                if (drag != null) {
                                    val target = reorderTarget(drag, currentClips.size, with(density) { ReorderSize.toPx() }, with(density) { ReorderGap.toPx() })
                                    if (target != drag.fromIndex) move(drag.clipId, target)
                                }
                            }
                        }

                        GestureMode.SCROLL, GestureMode.ZOOM -> {
                            scrubStart()
                            if (mode == GestureMode.SCROLL) {
                                state.scrollByPx(-moved)
                                scrub(state.positionUs)
                            }
                            val tracker = VelocityTracker()
                            tracker.addPosition(down.uptimeMillis, down.position)
                            var zoomed = mode == GestureMode.ZOOM
                            while (true) {
                                val event = awaitPointerEvent()
                                val pressed = event.changes.filter { it.pressed }
                                if (pressed.isEmpty()) break
                                if (pressed.size > 1) {
                                    zoomed = true
                                    val zoom = event.calculateZoom()
                                    if (zoom != 1f) state.zoomBy(zoom)
                                } else {
                                    val change = pressed.first()
                                    val dx = change.positionChange().x
                                    if (dx != 0f) {
                                        state.scrollByPx(-dx)
                                        scrub(state.positionUs)
                                    }
                                    tracker.addPosition(change.uptimeMillis, change.position)
                                }
                                event.changes.forEach { it.consume() }
                            }
                            val velocity = if (zoomed) 0f else -tracker.calculateVelocity().x
                            if (abs(velocity) < 50f) {
                                scrubEnd(state.positionUs)
                            } else {
                                fling[0] = scope.launch { flingTimeline(state, velocity, decay, scrub, scrubEnd) }
                            }
                        }

                        GestureMode.IGNORE -> Unit
                    }
                }
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawRuler(state, textMeasurer, labelStyle)
            if (reorder == null) {
                boxes.forEach { box ->
                    drawClip(box, state, frames, box.ui.clip.id == selectedClipId, trackTopPx, trackHeightPx)
                }
                boxes.firstOrNull { it.ui.clip.id == selectedClipId }?.let { box ->
                    drawDurationLabel(box, state, textMeasurer, trackTopPx)
                }
            }
        }

        if (reorder == null) {
            boxes.firstOrNull { it.ui.clip.id == selectedClipId }?.let { box ->
                TrimEdge.entries.forEach { edge ->
                    key(box.ui.clip.id, edge) {
                        TrimHandle(
                            edge = edge,
                            box = box,
                            state = state,
                            trackTopPx = trackTopPx,
                            halfWidth = { halfWidth },
                            onStart = {
                                val clip = box.ui.clip
                                trim = TrimDrag(clip.id, edge, clip.trimStartUs, clip.trimEndUs, snapped = false)
                            },
                            onDrag = { clip, accumulatedPx ->
                                val next = trimFor(clip, edge, accumulatedPx, state, with(density) { SnapDistance.toPx() })
                                if (next.snapped && trim?.snapped != true) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                trim = next
                            },
                            onEnd = { clip ->
                                val drag = trim
                                if (drag == null || (drag.trimStartUs == clip.trimStartUs && drag.trimEndUs == clip.trimEndUs)) {
                                    trim = null
                                } else {
                                    trim = drag.copy(committed = true)
                                    onTrim(clip.id, drag.trimStartUs, drag.trimEndUs)
                                }
                            },
                            onCancel = { trim = null },
                        )
                    }
                }
            }
        }

        reorder?.let { drag -> ReorderStrip(drag, clips, frames) }

        Canvas(Modifier.fillMaxSize()) { drawPlayhead() }

        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = TrackTop + (TrackHeight - 40.dp) / 2, end = 12.dp)
                .size(40.dp)
                .shadow(8.dp, RoundedCornerShape(10.dp))
                .clip(RoundedCornerShape(10.dp))
                .background(Color.White)
                .clickable(onClick = onAdd),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.Add, contentDescription = null, tint = Color.Black)
        }
    }
}

private suspend fun flingTimeline(
    state: TimelineState,
    velocity: Float,
    decay: DecayAnimationSpec<Float>,
    onScrub: (Long) -> Unit,
    onScrubEnd: (Long) -> Unit,
) {
    var last = 0f
    try {
        AnimationState(initialValue = 0f, initialVelocity = velocity).animateDecay(decay) {
            state.scrollByPx(value - last)
            last = value
            onScrub(state.positionUs)
            if (state.positionUs <= 0L || state.positionUs >= state.durationUs) cancelAnimation()
        }
    } finally {
        onScrubEnd(state.positionUs)
    }
}

private fun layoutClips(clips: List<ClipUi>, trim: TrimDrag?): List<ClipBox> {
    var start = 0L
    return clips.map { ui ->
        val clip = ui.clip
        if (trim != null && trim.clipId == clip.id) {
            val duration = ((trim.trimEndUs - trim.trimStartUs) / clip.speed.toDouble()).toLong()
            // Trimming the start keeps the clip's end in place so the edge follows the finger;
            // the track closes up once the trim is applied.
            val boxStart = if (trim.edge == TrimEdge.START) start + clip.durationUs - duration else start
            start = if (trim.edge == TrimEdge.START) start + clip.durationUs else start + duration
            ClipBox(ui, boxStart, duration, trim.trimStartUs)
        } else {
            ClipBox(ui, start, clip.durationUs, clip.trimStartUs).also { start += clip.durationUs }
        }
    }
}

/** The range a handle drag of [accumulatedPx] gives, snapped to the playhead when close to it. */
private fun trimFor(clip: MediaClip, edge: TrimEdge, accumulatedPx: Float, state: TimelineState, snapPx: Float): TrimDrag {
    val rawUs = (accumulatedPx / state.pxPerUs).toLong()
    val threshold = (snapPx / state.pxPerUs).toLong()
    val playhead = state.positionUs
    val edgeUs = (if (edge == TrimEdge.START) clip.startUs else clip.endUs) + rawUs
    val snapped = abs(edgeUs - playhead) < threshold
    val deltaUs = if (snapped) playhead - (if (edge == TrimEdge.START) clip.startUs else clip.endUs) else rawUs
    val (start, end) = if (clip.source.kind == MediaKind.IMAGE) {
        if (edge == TrimEdge.START) 0L to clip.durationUs - deltaUs else 0L to clip.durationUs + deltaUs
    } else {
        val sourceDelta = (deltaUs * clip.speed).toLong()
        if (edge == TrimEdge.START) clip.trimStartUs + sourceDelta to clip.trimEndUs else clip.trimStartUs to clip.trimEndUs + sourceDelta
    }
    val (clampedStart, clampedEnd) = MainTrackEdits.clampTrim(clip, start, end)
    return TrimDrag(clip.id, edge, clampedStart, clampedEnd, snapped)
}

private fun reorderTarget(drag: ReorderDrag, count: Int, size: Float, gap: Float): Int {
    val stripStart = drag.startX - drag.fromIndex * (size + gap) - size / 2
    return ((drag.x - stripStart - size / 2) / (size + gap)).roundToInt().coerceIn(0, count - 1)
}

@Composable
private fun TrimHandle(
    edge: TrimEdge,
    box: ClipBox,
    state: TimelineState,
    trackTopPx: Float,
    halfWidth: () -> Float,
    onStart: () -> Unit,
    onDrag: (clip: MediaClip, accumulatedPx: Float) -> Unit,
    onEnd: (clip: MediaClip) -> Unit,
    onCancel: () -> Unit,
) {
    val density = LocalDensity.current
    val handlePx = with(density) { HandleWidth.toPx() }
    val gapPx = with(density) { ClipGap.toPx() }
    val clip by rememberUpdatedState(box.ui.clip)
    val start by rememberUpdatedState(onStart)
    val drag by rememberUpdatedState(onDrag)
    val end by rememberUpdatedState(onEnd)
    val cancel by rememberUpdatedState(onCancel)
    val shape = if (edge == TrimEdge.START) {
        RoundedCornerShape(topStart = 8.dp, bottomStart = 8.dp)
    } else {
        RoundedCornerShape(topEnd = 8.dp, bottomEnd = 8.dp)
    }
    Box(
        modifier = Modifier
            .offset {
                // Read in the layout phase, so scrolling moves the handle without recomposing.
                val playheadX = halfWidth()
                val x = if (edge == TrimEdge.START) {
                    playheadX + (box.startUs - state.positionUs).toFloat() * state.pxPerUs + gapPx / 2 - handlePx
                } else {
                    playheadX + (box.endUs - state.positionUs).toFloat() * state.pxPerUs - gapPx / 2
                }
                IntOffset(x.roundToInt(), trackTopPx.roundToInt())
            }
            .size(HandleWidth, TrackHeight)
            .clip(shape)
            .background(Color.White)
            .pointerInput(Unit) {
                // Claim the touch so the timeline doesn't scroll or select underneath.
                awaitEachGesture { awaitFirstDown(requireUnconsumed = false).consume() }
            }
            .pointerInput(Unit) {
                var accumulated = 0f
                detectHorizontalDragGestures(
                    onDragStart = {
                        accumulated = 0f
                        start()
                    },
                    onDragEnd = { end(clip) },
                    onDragCancel = { cancel() },
                    onHorizontalDrag = { change, dx ->
                        change.consume()
                        accumulated += dx
                        drag(clip, accumulated)
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(width = 2.dp, height = 18.dp)
                .background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(1.dp)),
        )
    }
}

@Composable
private fun ReorderStrip(drag: ReorderDrag, clips: List<ClipUi>, frames: FilmstripLoader) {
    val density = LocalDensity.current
    val sizePx = with(density) { ReorderSize.toPx() }
    val gapPx = with(density) { ReorderGap.toPx() }
    val trackTopPx = with(density) { TrackTop.toPx() } + with(density) { (TrackHeight - ReorderSize).toPx() } / 2
    val target = reorderTarget(drag, clips.size, sizePx, gapPx)
    val stripStart = drag.startX - drag.fromIndex * (sizePx + gapPx) - sizePx / 2
    val others = clips.filterNot { it.clip.id == drag.clipId }
    val held = clips.firstOrNull { it.clip.id == drag.clipId } ?: return
    val order = others.toMutableList().apply { add(target, held) }

    order.forEachIndexed { slot, ui ->
        key(ui.clip.id) {
            val dragged = ui.clip.id == drag.clipId
            val slotX = stripStart + slot * (sizePx + gapPx)
            val animatedX by animateFloatAsState(
                targetValue = slotX,
                animationSpec = spring(dampingRatio = Spring.DampingRatioLowBouncy, stiffness = Spring.StiffnessMedium),
                label = "reorderSlot",
            )
            val x = if (dragged) drag.x - sizePx / 2 else animatedX
            val frame = frames[FrameKey(ui.frameUri, ui.clip.source.kind, frameTime(ui.clip, ui.clip.trimStartUs, 1_000_000L))]
            Box(
                modifier = Modifier
                    .offset { IntOffset(x.roundToInt(), trackTopPx.roundToInt()) }
                    .size(ReorderSize)
                    .graphicsLayer {
                        val scale = if (dragged) 1.12f else 1f
                        scaleX = scale
                        scaleY = scale
                    }
                    .shadow(if (dragged) 12.dp else 0.dp, RoundedCornerShape(10.dp))
                    .clip(RoundedCornerShape(10.dp))
                    .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                    .then(if (dragged) Modifier.border(2.dp, Color.White, RoundedCornerShape(10.dp)) else Modifier),
            ) {
                if (frame != null) {
                    Image(bitmap = frame, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                }
            }
        }
    }
}

/** Source time of a filmstrip frame, rounded to a grid so frames are reused across zoom levels. */
private fun frameTime(clip: MediaClip, sourceUs: Long, gridUs: Long): Long {
    if (clip.source.kind == MediaKind.IMAGE) return 0L
    val last = (MainTrackEdits.sourceDurationUs(clip) - 100_000L).coerceAtLeast(0L)
    return ((sourceUs.coerceIn(0L, last) / gridUs) * gridUs)
}

private fun DrawScope.drawRuler(state: TimelineState, textMeasurer: TextMeasurer, style: TextStyle) {
    val pxPerUs = state.pxPerUs
    val minMajorPx = 72.dp.toPx()
    val major = MAJOR_TICKS_US.firstOrNull { it * pxPerUs >= minMajorPx } ?: MAJOR_TICKS_US.last()
    val divisions = intArrayOf(10, 5, 4, 2, 1).first { (major / it) * pxPerUs >= 10.dp.toPx() || it == 1 }
    val minor = major / divisions
    val center = size.width / 2f
    val position = state.positionUs
    val fromUs = max(0L, position - (center / pxPerUs).toLong())
    val toUs = min(state.durationUs, position + (center / pxPerUs).toLong())
    var t = (fromUs / minor) * minor
    val baseline = RulerHeight.toPx() - 2.dp.toPx()
    while (t <= toUs) {
        val x = center + (t - position).toFloat() * pxPerUs
        if (t % major == 0L) {
            drawLine(FluroColors.OnSurfaceMuted, Offset(x, baseline - 8.dp.toPx()), Offset(x, baseline), strokeWidth = 1.dp.toPx())
            // Labels are measured without constraints: drawText(textMeasurer, text, topLeft) sizes
            // the text to "canvas width - x", which fails for labels past the right edge.
            val labelX = x + 3.dp.toPx()
            if (labelX < size.width) {
                drawText(textMeasurer.measure(formatDuration(t), style), topLeft = Offset(labelX, 0f))
            }
        } else {
            drawCircle(FluroColors.Outline, radius = 1.2.dp.toPx(), center = Offset(x, baseline - 2.dp.toPx()))
        }
        t += minor
    }
}

private fun DrawScope.drawClip(
    box: ClipBox,
    state: TimelineState,
    frames: FilmstripLoader,
    selected: Boolean,
    top: Float,
    height: Float,
) {
    val center = size.width / 2f
    val pxPerUs = state.pxPerUs
    val gap = ClipGap.toPx()
    val left = center + (box.startUs - state.positionUs).toFloat() * pxPerUs + gap / 2
    val right = center + (box.endUs - state.positionUs).toFloat() * pxPerUs - gap / 2
    if (right < 0f || left > size.width || right <= left) return
    val radius = 8.dp.toPx()
    val outline = Path().apply { addRoundRect(RoundRect(left, top, right, top + height, CornerRadius(radius))) }
    val clip = box.ui.clip

    clipPath(outline) {
        drawRect(FluroColors.SurfaceHighest, Offset(left, top), Size(right - left, height))
        // Square frames along the clip; only the visible ones are drawn and loaded.
        val tile = height
        val tileSourceUs = tile / pxPerUs * clip.speed
        var grid = 250_000L
        while (grid < tileSourceUs) grid *= 2
        val visibleLeft = max(left, 0f)
        val visibleRight = min(right, size.width)
        var i = floor((visibleLeft - left) / tile).toInt().coerceAtLeast(0)
        while (true) {
            val tx = left + i * tile
            if (tx > visibleRight) break
            val offsetUs = ((tx + tile / 2 - left) / pxPerUs).toLong()
            val sourceUs = box.trimStartUs + (offsetUs * clip.speed).toLong()
            frames[FrameKey(box.ui.frameUri, clip.source.kind, frameTime(clip, sourceUs, grid))]?.let {
                drawSquareFrame(it, tx, top, tile)
            }
            i++
        }
        if (!selected) drawRect(Color.Black.copy(alpha = 0.12f), Offset(left, top), Size(right - left, height))
    }
    if (selected) {
        drawRoundRect(
            color = Color.White,
            topLeft = Offset(left, top),
            size = Size(right - left, height),
            cornerRadius = CornerRadius(radius),
            style = Stroke(width = 2.dp.toPx()),
        )
    }
}

private fun DrawScope.drawSquareFrame(image: ImageBitmap, x: Float, y: Float, side: Float) {
    val crop = min(image.width, image.height)
    drawImage(
        image = image,
        srcOffset = IntOffset((image.width - crop) / 2, (image.height - crop) / 2),
        srcSize = IntSize(crop, crop),
        dstOffset = IntOffset(x.roundToInt(), y.roundToInt()),
        dstSize = IntSize(side.roundToInt() + 1, side.roundToInt()),
    )
}

private fun DrawScope.drawDurationLabel(box: ClipBox, state: TimelineState, textMeasurer: TextMeasurer, top: Float) {
    val center = size.width / 2f
    val left = center + (box.startUs - state.positionUs).toFloat() * state.pxPerUs
    val layout = textMeasurer.measure(formatDuration(box.durationUs), TextStyle(fontSize = 10.sp, color = Color.White))
    val pad = 4.dp.toPx()
    val x = left.coerceAtLeast(0f) + 6.dp.toPx()
    val y = top + 4.dp.toPx()
    drawRoundRect(
        color = Color.Black.copy(alpha = 0.6f),
        topLeft = Offset(x - pad, y),
        size = Size(layout.size.width + pad * 2, layout.size.height.toFloat()),
        cornerRadius = CornerRadius(4.dp.toPx()),
    )
    drawText(layout, topLeft = Offset(x, y))
}

private fun DrawScope.drawPlayhead() {
    val x = size.width / 2f
    val width = 2.dp.toPx()
    drawLine(
        brush = Brush.verticalGradient(listOf(Color.White, Color.White.copy(alpha = 0.85f))),
        start = Offset(x, 4.dp.toPx()),
        end = Offset(x, size.height),
        strokeWidth = width,
    )
    drawCircle(Color.White, radius = 4.dp.toPx(), center = Offset(x, 4.dp.toPx()))
}

private val MAJOR_TICKS_US = longArrayOf(1, 2, 5, 10, 15, 30, 60, 120, 300, 600).map { it * 1_000_000L }
