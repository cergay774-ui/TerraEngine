package com.flurocup.feature.editor.timeline

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import com.flurocup.core.model.MediaKind
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch

/**
 * Scroll position and zoom of the timeline. The playhead sits in the middle of the view, so the
 * scroll position is the playhead time.
 */
@Stable
class TimelineState(initialPxPerSecond: Float, private val minPxPerSecond: Float, private val maxPxPerSecond: Float) {
    var positionUs by mutableLongStateOf(0L)
    var durationUs by mutableLongStateOf(0L)
    var pxPerSecond by mutableFloatStateOf(initialPxPerSecond)
        private set

    val pxPerUs: Float get() = pxPerSecond / 1_000_000f

    fun scrollToUs(us: Long) {
        positionUs = us.coerceIn(0L, durationUs.coerceAtLeast(0L))
    }

    fun scrollByPx(dx: Float) = scrollToUs(positionUs + (dx / pxPerUs).toLong())

    fun zoomBy(factor: Float) {
        pxPerSecond = (pxPerSecond * factor).coerceIn(minPxPerSecond, maxPxPerSecond)
    }
}

/** One filmstrip frame: a file, and a time in it rounded to the timeline's frame grid. */
data class FrameKey(val uri: String, val kind: MediaKind, val timeUs: Long)

/**
 * Loads filmstrip frames on demand. The timeline asks for frames while drawing; missing ones are
 * fetched in the background and the timeline redraws when they arrive.
 */
@Stable
class FilmstripLoader(scope: CoroutineScope, private val load: suspend (FrameKey) -> ImageBitmap?) {
    private val frames = mutableStateMapOf<FrameKey, ImageBitmap>()
    private val requested = HashSet<FrameKey>()
    private val queue = Channel<FrameKey>(Channel.UNLIMITED)

    init {
        repeat(WORKERS) {
            scope.launch {
                for (key in queue) {
                    // A frame that can't be read stays blank; it must never take the editor down.
                    val frame = try {
                        load(key)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        null
                    }
                    if (frame != null) frames[key] = frame
                }
            }
        }
    }

    /** The frame if it is loaded; otherwise null, and the frame is queued. Call from the main thread. */
    operator fun get(key: FrameKey): ImageBitmap? {
        frames[key]?.let { return it }
        if (requested.add(key)) queue.trySend(key)
        return null
    }

    private companion object {
        const val WORKERS = 2
    }
}
