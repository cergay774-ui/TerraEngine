package com.flurocup.core.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.MatrixTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flurocup.core.engine.composition.CompositionBuilder
import com.flurocup.core.engine.composition.RenderSpec
import com.flurocup.core.engine.effects.EffectLibrary
import com.flurocup.core.engine.effects.FrameInterpolationEffect
import com.flurocup.core.engine.effects.LiveLooks
import com.flurocup.core.engine.media.runTransformer
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaInfo
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project
import com.flurocup.core.model.edit.MainTrackEdits
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith

/** Exports a moving square at 120 fps from 30 fps and checks the frames in between. */
@UnstableApi
@RunWith(AndroidJUnit4::class)
class FrameInterpolationDeviceTest {

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun smoothExportMakesFramesAlongTheMotion() {
        val out = export(smooth = true)
        val frames = frameCount(out)
        assertTrue("expected about 120 frames, got $frames", frames in 110..125)
        val xs = centroids(out, 30..45)
        Log.i(TAG, "smooth centroids: $xs")
        val steps = xs.zipWithNext { a, b -> b - a }
        assertTrue("square must move on every frame: $xs", steps.all { it > 0.4f })
        assertTrue("steps must be even: $steps", steps.max() < steps.min() * 4f)
    }

    @Test
    fun plainHighRateRepeatsFrames() {
        val out = export(smooth = false)
        val frames = frameCount(out)
        assertTrue("expected about 120 frames, got $frames", frames in 110..125)
        val xs = centroids(out, 30..45)
        Log.i(TAG, "repeat centroids: $xs")
        val still = xs.zipWithNext { a, b -> b - a }.count { kotlin.math.abs(it) < 0.4f }
        assertTrue("repeated frames expected: $xs", still >= 8)
    }

    private fun export(smooth: Boolean): File {
        val clip = MediaClip(
            id = "main",
            startUs = 0,
            source = MediaSource(Uri.fromFile(video).toString(), MediaKind.VIDEO, MediaInfo(WIDTH, HEIGHT, frameRate = 30f, durationUs = DURATION_US)),
            trimStartUs = 0,
            trimEndUs = DURATION_US,
        )
        val project = MainTrackEdits.withClips(Project("p", "test", 0, 0), listOf(clip))
        val builder = CompositionBuilder(context, EffectLibrary(context))
        val spec = RenderSpec(WIDTH, HEIGHT, 30f, uriFor = { it.source.uri }, lookFor = LiveLooks()::forClip)
        val composition = checkNotNull(builder.video(project, spec, listOf(FrameInterpolationEffect(120f, smooth)), forExport = true))
        val out = File(context.cacheDir, "interpolated_$smooth.mp4").apply { delete() }
        runBlocking { withContext(Dispatchers.Main) { runTransformer(context, composition, out.path, {}, {}) } }
        return out
    }

    private fun frameCount(file: File): Int {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.path)
            val track = (0 until extractor.trackCount).first {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)!!.startsWith("video/")
            }
            extractor.selectTrack(track)
            var count = 0
            while (extractor.sampleTime >= 0) {
                count++
                extractor.advance()
            }
            return count
        } finally {
            extractor.release()
        }
    }

    /** Horizontal centre of the bright square in each of [frames]. */
    private fun centroids(file: File, frames: IntRange): List<Float> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.path)
            return frames.map { index ->
                val bitmap = checkNotNull(retriever.getFrameAtIndex(index)) { "no frame $index" }
                var sum = 0.0
                var weight = 0.0
                for (y in 0 until bitmap.height step 2) {
                    for (x in 0 until bitmap.width) {
                        val c = bitmap.getPixel(x, y)
                        val l = (Color.red(c) + Color.green(c) + Color.blue(c)) / 3.0
                        if (l > 128) {
                            sum += x * l
                            weight += l
                        }
                    }
                }
                bitmap.recycle()
                (sum / weight.coerceAtLeast(1.0)).toFloat()
            }
        } finally {
            retriever.release()
        }
    }

    companion object {
        private const val TAG = "FrameInterpolationTest"
        private const val WIDTH = 320
        private const val HEIGHT = 240
        private const val DURATION_US = 1_000_000L
        private lateinit var video: File

        /** One second at 30 fps of a white square crossing a black frame from left to right. */
        @JvmStatic
        @BeforeClass
        fun makeVideo() {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val png = File(context.cacheDir, "square.png")
            val bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
            Canvas(bitmap).apply {
                drawColor(Color.BLACK)
                drawRect(WIDTH / 2f - 20f, HEIGHT / 2f - 20f, WIDTH / 2f + 20f, HEIGHT / 2f + 20f, Paint().apply { color = Color.WHITE })
            }
            png.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            val move = MatrixTransformation { timeUs ->
                // From 0.6 of the half-width left of centre to 0.6 right, over the second.
                Matrix().apply { setTranslate(-0.6f + 1.2f * (timeUs / DURATION_US.toFloat()), 0f) }
            }
            val item = EditedMediaItem.Builder(MediaItem.Builder().setUri(Uri.fromFile(png)).setImageDurationMs(DURATION_US / 1000).build())
                .setFrameRate(30)
                .setEffects(Effects(emptyList(), listOf(move)))
                .build()
            val composition = Composition.Builder(EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO)).addItem(item).build()).build()
            video = File(context.cacheDir, "square.mp4").apply { delete() }
            runBlocking { withContext(Dispatchers.Main) { runTransformer(context, composition, video.path, {}, {}) } }
            check(video.length() > 0) { "test video was not written" }
        }
    }
}
