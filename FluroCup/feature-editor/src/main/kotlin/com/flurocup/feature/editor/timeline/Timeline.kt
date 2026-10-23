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
import androidx.compose.ui.graphics.drawscope.clipRect
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
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
import com.flurocup.feature.editor.OverlayTrackUi
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class TrimEdge { START, END }

/**
 * A handle drag in progress: the range the clip would get, shown live before it is applied.
 * For overlays [startUs] is where the clip would start; main clips don't move on their own.
 */
private data class TrimDrag(
    val clipId: String,
    val edge: TrimEdge,
    val trimStartUs: Long,
    val trimEndUs: Long,
    val startUs: Long,
    val snapped: Boolean,
    val committed: Boolean = false,
)

/** A long-press reorder of the main track in progress. */
private data class ReorderDrag(val clipId: String, val fromIndex: Int, val startX: Float, val x: Float)

/** A long-press move of an overlay in progress; [row] counts rows from the top, -1 means a new top row. */
private data class OverlayDrag(val clipId: String, val grabOffsetUs: Long, val startUs: Long, val row: Int, val snapped: Boolean)

/** Where a clip is drawn, which during a drag differs from where the project has it. */
private data class ClipBox(val ui: ClipUi, val startUs: Long, val durationUs: Long, val trimStartUs: Long, val row: Int = MAIN_ROW) {
    val endUs: Long get() = startUs + durationUs
}

private enum class GestureMode { TAP, SCROLL, VERTICAL_SCROLL, ZOOM, LONG_PRESS, IGNORE }

private const val MAIN_ROW = Int.MAX_VALUE
private val RulerHeight = 24.dp
private val TrackTop = 30.dp
private val TrackHeight = 56.dp
private val OverlayRowHeight = 40.dp
private val RowGap = 6.dp
private const val VISIBLE_OVERLAY_ROWS = 2
private val HandleWidth = 14.dp
private val ClipGap = 2.dp
private val SnapDistance = 12.dp
private val ReorderSize = 52.dp
private val ReorderGap = 8.dp

/**
 * The timeline: playhead fixed in the middle, drag to scroll (with fling), pinch to zoom,
 * filmstrip frames on clips. Overlay tracks sit above the main track, top layer first, with
 * effect tracks above them, and all of these scroll vertically when there are many. Tap selects; a selected clip's edges trim; long-press
 * reorders main clips or moves an overlay in time and between layers. Edges snap to the
 * playhead and to other clips' edges with a haptic tick.
 */
@Composable
internal fun Timeline(
    state: TimelineState,
    clips: List<ClipUi>,
    overlays: List<OverlayTrackUi>,
    effects: List<OverlayTrackUi>,
    selectedClipId: String?,
    frames: FilmstripLoader,
    onScrubStart: () -> Unit,
    onScrub: (positionUs: Long) -> Unit,
    onScrubEnd: (positionUs: Long) -> Unit,
    onSelect: (clipId: String?) -> Unit,
    onTrim: (clipId: String, trimStartUs: Long, trimEndUs: Long) -> Unit,
    onMove: (clipId: String, toIndex: Int) -> Unit,
    onTrimOverlay: (clipId: String, startUs: Long, trimStartUs: Long, trimEndUs: Long) -> Unit,
    onMoveOverlay: (clipId: String, startUs: Long, row: Int) -> Unit,
    onTrimEffect: (id: String, startUs: Long, durationUs: Long) -> Unit,
    onMoveEffect: (id: String, startUs: Long, row: Int) -> Unit,
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
    var overlayDrag by remember { mutableStateOf<OverlayDrag?>(null) }
    var overlayScroll by remember { mutableFloatStateOf(0f) }
    var halfWidth by remember { mutableFloatStateOf(0f) }

    val trackTopPx = with(density) { TrackTop.toPx() }
    val rowHeightPx = with(density) { OverlayRowHeight.toPx() }
    val rowStepPx = with(density) { (OverlayRowHeight + RowGap).toPx() }
    val mainHeightPx = with(density) { TrackHeight.toPx() }
    val snapPx = with(density) { SnapDistance.toPx() }
    // Rows above the main track: effect tracks, then overlay tracks, both top first.
    val upperRows = remember(effects, overlays) { effects + overlays }
    val effectRows = effects.size
    val rows = upperRows.size
    val overlayViewport = (OverlayRowHeight + RowGap) * min(rows, VISIBLE_OVERLAY_ROWS)
    val overlayViewportPx = with(density) { overlayViewport.toPx() }
    val maxOverlayScroll = max(0f, rows * rowStepPx - overlayViewportPx)
    val mainTop = TrackTop + overlayViewport
    val mainTopPx = with(density) { mainTop.toPx() }
    LaunchedEffect(maxOverlayScroll) { overlayScroll = overlayScroll.coerceIn(0f, maxOverlayScroll) }

    val mainBoxes = remember(clips, trim) { layoutMain(clips, trim) }
    val overlayBoxes = remember(upperRows, trim) { layoutOverlays(upperRows, trim) }
    val allBoxes = mainBoxes + overlayBoxes

    // A committed edit keeps showing until the project catches up, so the clip doesn't jump back.
    LaunchedEffect(clips, upperRows) { if (trim?.committed == true) trim = null }
    LaunchedEffect(trim?.committed) {
        if (trim?.committed == true) {
            delay(800)
            trim = null
        }
    }

    val currentMain by rememberUpdatedState(mainBoxes)
    val currentOverlays by rememberUpdatedState(overlayBoxes)
    val currentClips by rememberUpdatedState(clips)
    val currentRows by rememberUpdatedState(rows)
    val currentEffectRows by rememberUpdatedState(effectRows)
    val currentMaxScroll by rememberUpdatedState(maxOverlayScroll)
    val currentMainTop by rememberUpdatedState(mainTopPx)
    val currentViewport by rememberUpdatedState(overlayViewportPx)
    val scrubStart by rememberUpdatedState(onScrubStart)
    val scrub by rememberUpdatedState(onScrub)
    val scrubEnd by rememberUpdatedState(onScrubEnd)
    val select by rememberUpdatedState(onSelect)
    val move by rememberUpdatedState(onMove)
    val moveOverlay by rememberUpdatedState(onMoveOverlay)
    val moveEffect by rememberUpdatedState(onMoveEffect)
    val fling = remember { arrayOfNulls<Job>(1) }

    fun rowTop(row: Int): Float = if (row == MAIN_ROW) mainTopPx else trackTopPx + row * rowStepPx - overlayScroll

    /** Edges other clips could snap to, besides the playhead. */
    fun snapTargets(exceptId: String): List<Long> =
        (currentMain + currentOverlays).filter { it.ui.clip.id != exceptId }.flatMap { listOf(it.startUs, it.endUs) }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(mainTop + TrackHeight + 10.dp)
            .onSizeChanged { halfWidth = it.width / 2f }
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    fling[0]?.cancel()
                    var movedX = 0f
                    var movedY = 0f
                    val inOverlays = down.position.y >= trackTopPx && down.position.y < trackTopPx + currentViewport
                    val mode = if (down.isConsumed) {
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
                                movedX += change.positionChange().x
                                movedY += change.positionChange().y
                                if (abs(movedX) > viewConfiguration.touchSlop || abs(movedY) > viewConfiguration.touchSlop) {
                                    result = if (abs(movedY) > abs(movedX) && inOverlays && currentMaxScroll > 0f) {
                                        GestureMode.VERTICAL_SCROLL
                                    } else {
                                        GestureMode.SCROLL
                                    }
                                    break
                                }
                            }
                            result
                        } ?: GestureMode.LONG_PRESS
                    }

                    fun timeAt(x: Float) = state.positionUs + ((x - size.width / 2f) / state.pxPerUs).toLong()
                    fun onMain(y: Float) = y >= currentMainTop && y <= currentMainTop + mainHeightPx
                    fun overlayRowAt(y: Float): Int? {
                        if (y < trackTopPx || y >= trackTopPx + currentViewport) return null
                        val row = floor((y - trackTopPx + overlayScroll) / rowStepPx).toInt()
                        val inRow = (y - trackTopPx + overlayScroll) - row * rowStepPx <= rowHeightPx
                        return row.takeIf { inRow && it in 0 until currentRows }
                    }
                    fun clipAt(position: Offset): ClipBox? {
                        val time = timeAt(position.x)
                        val row = overlayRowAt(position.y)
                        val candidates = when {
                            row != null -> currentOverlays.filter { it.row == row }
                            onMain(position.y) -> currentMain
                            else -> emptyList()
                        }
                        return candidates.firstOrNull { time >= it.startUs && time < it.endUs }
                    }

                    when (mode) {
                        GestureMode.TAP -> {
                            val position = down.position
                            if (position.y < trackTopPx) {
                                // Tapping the ruler moves the playhead there.
                                scrubStart()
                                state.scrollToUs(timeAt(position.x))
                                scrubEnd(state.positionUs)
                            } else {
                                select(clipAt(position)?.ui?.clip?.id)
                            }
                        }

                        GestureMode.LONG_PRESS -> {
                            val box = clipAt(down.position)
                            if (box != null && box.row != MAIN_ROW) {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                select(box.ui.clip.id)
                                val grab = timeAt(down.position.x) - box.startUs
                                overlayDrag = OverlayDrag(box.ui.clip.id, grab, box.startUs, box.row, snapped = false)
                                while (true) {
                                    val event = awaitPointerEvent()
                                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                    if (!change.pressed) break
                                    change.consume()
                                    val rawStart = max(0L, timeAt(change.position.x) - grab)
                                    val threshold = (snapPx / state.pxPerUs).toLong()
                                    val targets = snapTargets(box.ui.clip.id) + state.positionUs
                                    val snapStart = targets.minByOrNull { abs(it - rawStart) }?.takeIf { abs(it - rawStart) < threshold }
                                    val snapEnd = targets.minByOrNull { abs(it - (rawStart + box.durationUs)) }
                                        ?.takeIf { abs(it - (rawStart + box.durationUs)) < threshold }
                                    val start = when {
                                        snapStart != null -> snapStart
                                        snapEnd != null -> max(0L, snapEnd - box.durationUs)
                                        else -> rawStart
                                    }
                                    val snapped = snapStart != null || snapEnd != null
                                    val rawRow = floor((change.position.y - trackTopPx + overlayScroll) / rowStepPx).toInt()
                                    // Effects stay among effect rows and overlays among overlay rows; the
                                    // row just above a group's top one means a new track on top of it.
                                    val row = if (box.ui.effect != null) {
                                        rawRow.coerceIn(-1, currentEffectRows - 1)
                                    } else {
                                        rawRow.coerceIn(currentEffectRows - 1, currentRows - 1)
                                    }
                                    val previous = overlayDrag
                                    if (snapped && previous?.snapped != true) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    overlayDrag = previous?.copy(startUs = start, row = row, snapped = snapped)
                                }
                                val drag = overlayDrag
                                overlayDrag = null
                                if (drag != null && (drag.startUs != box.startUs || drag.row != box.row)) {
                                    if (box.ui.effect != null) {
                                        moveEffect(drag.clipId, drag.startUs, drag.row)
                                    } else {
                                        moveOverlay(drag.clipId, drag.startUs, (drag.row - currentEffectRows).coerceAtLeast(-1))
                                    }
                                }
                            } else if (box != null && currentClips.size > 1) {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                val index = currentMain.indexOf(box)
                                reorder = ReorderDrag(box.ui.clip.id, index, down.position.x, down.position.x)
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
                                    val target = reorderTarget(drag, currentClips.size, ReorderSize.toPx(), ReorderGap.toPx())
                                    if (target != drag.fromIndex) move(drag.clipId, target)
                                }
                            }
                        }

                        GestureMode.VERTICAL_SCROLL -> {
                            overlayScroll = (overlayScroll - movedY).coerceIn(0f, currentMaxScroll)
                            while (true) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                if (!change.pressed) break
                                overlayScroll = (overlayScroll - change.positionChange().y).coerceIn(0f, currentMaxScroll)
                                change.consume()
                            }
                        }

                        GestureMode.SCROLL, GestureMode.ZOOM -> {
                            scrubStart()
                            if (mode == GestureMode.SCROLL) {
                                state.scrollByPx(-movedX)
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
            val dragging = overlayDrag
            if (rows > 0) {
                clipRect(top = trackTopPx - 1f, bottom = trackTopPx + overlayViewportPx) {
                    for (row in 0 until rows) {
                        drawRect(
                            color = FluroColors.Contrast.copy(alpha = 0.04f),
                            topLeft = Offset(0f, rowTop(row)),
                            size = Size(size.width, rowHeightPx),
                        )
                    }
                    overlayBoxes.forEach { box ->
                        if (box.ui.clip.id != dragging?.clipId) {
                            val selected = box.ui.clip.id == selectedClipId
                            if (box.ui.effect != null) {
                                drawEffect(box, state, textMeasurer, selected, rowTop(box.row), rowHeightPx, dragged = false)
                            } else {
                                drawClip(box, state, frames, selected, rowTop(box.row), rowHeightPx, FluroColors.Violet)
                            }
                        }
                    }
                }
            }
            if (reorder == null) {
                mainBoxes.forEach { box ->
                    drawClip(box, state, frames, box.ui.clip.id == selectedClipId, mainTopPx, mainHeightPx, accent = null)
                }
            }
            if (dragging != null) {
                overlayBoxes.firstOrNull { it.ui.clip.id == dragging.clipId }?.let { box ->
                    val moved = box.copy(startUs = dragging.startUs, row = dragging.row)
                    if (box.ui.effect != null) {
                        drawEffect(moved, state, textMeasurer, selected = true, top = rowTop(dragging.row), height = rowHeightPx, dragged = true)
                    } else {
                        drawClip(moved, state, frames, selected = true, top = rowTop(dragging.row), height = rowHeightPx, accent = FluroColors.Teal)
                    }
                }
            }
            if (reorder == null && dragging == null) {
                allBoxes.firstOrNull { it.ui.clip.id == selectedClipId }?.let { box ->
                    drawDurationLabel(box, state, textMeasurer, rowTop(box.row))
                }
            }
        }

        if (reorder == null && overlayDrag == null) {
            allBoxes.firstOrNull { it.ui.clip.id == selectedClipId }?.let { box ->
                val isOverlay = box.row != MAIN_ROW
                TrimEdge.entries.forEach { edge ->
                    key(box.ui.clip.id, edge) {
                        TrimHandle(
                            edge = edge,
                            box = box,
                            state = state,
                            top = { rowTop(box.row) },
                            height = if (isOverlay) OverlayRowHeight else TrackHeight,
                            halfWidth = { halfWidth },
                            onStart = {
                                val clip = box.ui.clip
                                trim = TrimDrag(clip.id, edge, clip.trimStartUs, clip.trimEndUs, clip.startUs, snapped = false)
                            },
                            onDrag = { clip, accumulatedPx ->
                                val targets = snapTargets(clip.id) + state.positionUs
                                val next = if (isOverlay) {
                                    val rowClips = upperRows.getOrNull(box.row)?.clips?.map { it.clip }.orEmpty()
                                    overlayTrimFor(clip, rowClips, edge, accumulatedPx, state, snapPx, targets)
                                } else {
                                    mainTrimFor(clip, edge, accumulatedPx, state, snapPx, targets)
                                }
                                if (next.snapped && trim?.snapped != true) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                trim = next
                            },
                            onEnd = { clip ->
                                val drag = trim
                                val unchanged = drag == null ||
                                    (drag.trimStartUs == clip.trimStartUs && drag.trimEndUs == clip.trimEndUs && drag.startUs == clip.startUs)
                                if (unchanged || drag == null) {
                                    trim = null
                                } else {
                                    trim = drag.copy(committed = true)
                                    if (box.ui.effect != null) {
                                        onTrimEffect(clip.id, drag.startUs, drag.trimEndUs - drag.trimStartUs)
                                    } else if (isOverlay) {
                                        onTrimOverlay(clip.id, drag.startUs, drag.trimStartUs, drag.trimEndUs)
                                    } else {
                                        onTrim(clip.id, drag.trimStartUs, drag.trimEndUs)
                                    }
                                }
                            },
                            onCancel = { trim = null },
                        )
                    }
                }
            }
        }

        reorder?.let { drag -> ReorderStrip(drag, clips, frames, mainTopPx) }

        Canvas(Modifier.fillMaxSize()) { drawPlayhead() }

        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = mainTop + (TrackHeight - 40.dp) / 2, end = 12.dp)
                .size(40.dp)
                .shadow(8.dp, RoundedCornerShape(10.dp))
                .clip(RoundedCornerShape(10.dp))
                .background(FluroColors.Contrast)
                .clickable(onClick = onAdd),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.Add, contentDescription = null, tint = FluroColors.OnContrast)
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

private fun layoutMain(clips: List<ClipUi>, trim: TrimDrag?): List<ClipBox> {
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

private fun layoutOverlays(overlays: List<OverlayTrackUi>, trim: TrimDrag?): List<ClipBox> =
    overlays.flatMapIndexed { row, track ->
        track.clips.map { ui ->
            val clip = ui.clip
            if (trim != null && trim.clipId == clip.id) {
                val duration = ((trim.trimEndUs - trim.trimStartUs) / clip.speed.toDouble()).toLong()
                ClipBox(ui, trim.startUs, duration, trim.trimStartUs, row)
            } else {
                ClipBox(ui, clip.startUs, clip.durationUs, clip.trimStartUs, row)
            }
        }
    }

/** Moves [edgeUs] onto the nearest of [targets] within [snapPx]; returns the edge and whether it snapped. */
private fun snap(edgeUs: Long, targets: List<Long>, state: TimelineState, snapPx: Float): Pair<Long, Boolean> {
    val threshold = (snapPx / state.pxPerUs).toLong()
    val nearest = targets.minByOrNull { abs(it - edgeUs) } ?: return edgeUs to false
    return if (abs(nearest - edgeUs) < threshold) nearest to true else edgeUs to false
}

/** The range a main-clip handle drag of [accumulatedPx] gives, snapped to the playhead or other clips' edges. */
private fun mainTrimFor(
    clip: MediaClip,
    edge: TrimEdge,
    accumulatedPx: Float,
    state: TimelineState,
    snapPx: Float,
    targets: List<Long>,
): TrimDrag {
    val rawUs = (accumulatedPx / state.pxPerUs).toLong()
    val baseEdge = if (edge == TrimEdge.START) clip.startUs else clip.endUs
    val (snappedEdge, snapped) = snap(baseEdge + rawUs, targets, state, snapPx)
    val deltaUs = snappedEdge - baseEdge
    val (start, end) = if (clip.source.kind == MediaKind.IMAGE) {
        if (edge == TrimEdge.START) 0L to clip.durationUs - deltaUs else 0L to clip.durationUs + deltaUs
    } else {
        val sourceDelta = (deltaUs * clip.speed).toLong()
        if (edge == TrimEdge.START) clip.trimStartUs + sourceDelta to clip.trimEndUs else clip.trimStartUs to clip.trimEndUs + sourceDelta
    }
    val (clampedStart, clampedEnd) = MainTrackEdits.clampTrim(clip, start, end)
    return TrimDrag(clip.id, edge, clampedStart, clampedEnd, clip.startUs, snapped)
}

/**
 * The same for an overlay, which moves when its start is trimmed and must stay clear of the
 * clips beside it on its track ([rowClips]).
 */
private fun overlayTrimFor(
    clip: MediaClip,
    rowClips: List<MediaClip>,
    edge: TrimEdge,
    accumulatedPx: Float,
    state: TimelineState,
    snapPx: Float,
    targets: List<Long>,
): TrimDrag {
    val others = rowClips.filter { it.id != clip.id }
    val lower = others.filter { it.endUs <= clip.startUs }.maxOfOrNull { it.endUs } ?: 0L
    val upper = others.filter { it.startUs >= clip.endUs }.minOfOrNull { it.startUs } ?: Long.MAX_VALUE
    val rawUs = (accumulatedPx / state.pxPerUs).toLong()
    return if (edge == TrimEdge.START) {
        val (edgeUs, snapped) = snap(clip.startUs + rawUs, targets, state, snapPx)
        val delta = edgeUs.coerceAtLeast(lower) - clip.startUs
        val (start, end) = if (clip.source.kind == MediaKind.IMAGE) {
            0L to clip.durationUs - delta
        } else {
            clip.trimStartUs + (delta * clip.speed).toLong() to clip.trimEndUs
        }
        val (s, e) = MainTrackEdits.clampTrim(clip, start, end)
        val duration = ((e - s) / clip.speed.toDouble()).toLong()
        // The end stays put; the start follows the finger.
        TrimDrag(clip.id, edge, s, e, clip.endUs - duration, snapped)
    } else {
        val (edgeUs, snapped) = snap(clip.endUs + rawUs, targets, state, snapPx)
        val delta = edgeUs.coerceAtMost(upper) - clip.endUs
        val (start, end) = if (clip.source.kind == MediaKind.IMAGE) {
            0L to clip.durationUs + delta
        } else {
            clip.trimStartUs to clip.trimEndUs + (delta * clip.speed).toLong()
        }
        val (s, e) = MainTrackEdits.clampTrim(clip, start, end)
        TrimDrag(clip.id, edge, s, e, clip.startUs, snapped)
    }
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
    top: () -> Float,
    height: androidx.compose.ui.unit.Dp,
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
                IntOffset(x.roundToInt(), top().roundToInt())
            }
            .size(HandleWidth, height)
            .clip(shape)
            .background(FluroColors.Contrast)
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
                .background(FluroColors.OnContrast.copy(alpha = 0.45f), RoundedCornerShape(1.dp)),
        )
    }
}

@Composable
private fun ReorderStrip(drag: ReorderDrag, clips: List<ClipUi>, frames: FilmstripLoader, mainTopPx: Float) {
    val density = LocalDensity.current
    val sizePx = with(density) { ReorderSize.toPx() }
    val gapPx = with(density) { ReorderGap.toPx() }
    val trackTopPx = mainTopPx + with(density) { (TrackHeight - ReorderSize).toPx() } / 2
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
                    .then(if (dragged) Modifier.border(2.dp, FluroColors.Contrast, RoundedCornerShape(10.dp)) else Modifier),
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
    accent: Color?,
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
        if (accent != null) drawRect(accent.copy(alpha = 0.18f), Offset(left, top), Size(right - left, height))
        if (!selected) drawRect(Color.Black.copy(alpha = 0.12f), Offset(left, top), Size(right - left, height))
    }
    if (accent != null && !selected) {
        drawRoundRect(
            color = accent.copy(alpha = 0.7f),
            topLeft = Offset(left, top),
            size = Size(right - left, height),
            cornerRadius = CornerRadius(radius),
            style = Stroke(width = 1.dp.toPx()),
        )
    }
    if (selected) {
        drawRoundRect(
            color = FluroColors.Contrast,
            topLeft = Offset(left, top),
            size = Size(right - left, height),
            cornerRadius = CornerRadius(radius),
            style = Stroke(width = 2.dp.toPx()),
        )
    }
}

/** An effect on its track: a coloured bar with the effect's name. */
private fun DrawScope.drawEffect(
    box: ClipBox,
    state: TimelineState,
    textMeasurer: TextMeasurer,
    selected: Boolean,
    top: Float,
    height: Float,
    dragged: Boolean,
) {
    val center = size.width / 2f
    val gap = ClipGap.toPx()
    val left = center + (box.startUs - state.positionUs).toFloat() * state.pxPerUs + gap / 2
    val right = center + (box.endUs - state.positionUs).toFloat() * state.pxPerUs - gap / 2
    if (right < 0f || left > size.width || right <= left) return
    val radius = 8.dp.toPx()
    val alpha = if (selected || dragged) 0.95f else 0.7f
    drawRoundRect(
        brush = Brush.horizontalGradient(
            listOf(FluroColors.Orchid.copy(alpha = alpha), FluroColors.Violet.copy(alpha = alpha)),
            startX = left,
            endX = right,
        ),
        topLeft = Offset(left, top),
        size = Size(right - left, height),
        cornerRadius = CornerRadius(radius),
    )
    val label = box.ui.label.orEmpty()
    val textLeft = max(left, 0f) + 8.dp.toPx()
    val maxWidth = (min(right, size.width) - textLeft - 4.dp.toPx()).toInt()
    if (label.isNotEmpty() && maxWidth > 12.dp.toPx()) {
        val layout = textMeasurer.measure(
            text = "✦ $label",
            style = TextStyle(fontSize = 11.sp, color = Color.White),
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Ellipsis,
            constraints = Constraints(maxWidth = maxWidth),
        )
        drawText(layout, topLeft = Offset(textLeft, top + (height - layout.size.height) / 2))
    }
    if (selected) {
        drawRoundRect(
            color = FluroColors.Contrast,
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
        brush = Brush.verticalGradient(listOf(FluroColors.Contrast, FluroColors.Contrast.copy(alpha = 0.85f))),
        start = Offset(x, 4.dp.toPx()),
        end = Offset(x, size.height),
        strokeWidth = width,
    )
    drawCircle(FluroColors.Contrast, radius = 4.dp.toPx(), center = Offset(x, 4.dp.toPx()))
}

private val MAJOR_TICKS_US = longArrayOf(1, 2, 5, 10, 15, 30, 60, 120, 300, 600).map { it * 1_000_000L }
