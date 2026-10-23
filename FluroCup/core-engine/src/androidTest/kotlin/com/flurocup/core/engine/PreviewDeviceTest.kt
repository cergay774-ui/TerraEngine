package com.flurocup.core.engine

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.media.ImageReader
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import android.view.SurfaceHolder
import androidx.media3.common.MediaItem
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flurocup.core.engine.composition.CompositionBuilder
import com.flurocup.core.engine.composition.RenderSpec
import com.flurocup.core.engine.effects.ClipLookEffect
import com.flurocup.core.engine.effects.EffectLibrary
import com.flurocup.core.engine.effects.LiveLooks
import com.flurocup.core.engine.effects.ShaderEffect
import com.flurocup.core.engine.media.runTransformer
import com.flurocup.core.engine.preview.PreviewEngine
import com.flurocup.core.model.ClipEffect
import com.flurocup.core.model.ClipTransform
import com.flurocup.core.model.EffectItem
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaInfo
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project
import com.flurocup.core.model.edit.EffectEdits
import com.flurocup.core.model.edit.MainTrackEdits
import com.flurocup.core.model.edit.OverlayEdits
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Plays projects through the real preview engine on a device and checks that frames come out,
 * and compiles every effect shader on the device's GPU driver.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.ExperimentalApi::class)
@UnstableApi
@RunWith(AndroidJUnit4::class)
class PreviewDeviceTest {

    private val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val library by lazy { EffectLibrary(context) }
    private val builder by lazy { CompositionBuilder(context, library) }

    @Test
    fun everyShaderCompilesOnTheGpu() {
        val display = GlUtil.getDefaultEglDisplay()
        val eglContext = GlUtil.createEglContext(display)
        GlUtil.createFocusedPlaceholderEglSurface(eglContext, display)
        val failures = mutableListOf<String>()
        val shaders = library.catalog.effects.map { it.id to library.fragmentShader(it) } + ("clip_look" to ClipLookEffect.SHADER)
        shaders.forEach { (id, source) ->
            try {
                GlProgram(ShaderEffect.VERTEX_SHADER, source).delete()
            } catch (e: Exception) {
                failures += "$id: ${e.message}"
            }
        }
        failures.forEach { Log.e(TAG, "Shader failed: $it") }
        assertEquals(failures.joinToString("\n"), 0, failures.size)
    }

    @Test
    fun plainProjectPlays() = assertPlays(plainProject())

    @Test
    fun plainProjectWithEffectsPlays() = assertPlays(withEffects(plainProject()))

    @Test
    fun layeredProjectPlays() = assertPlays(layered(plainProject()))

    @Test
    fun layeredProjectWithEffectsPlays() = assertPlays(withEffects(layered(plainProject())))

    @Test
    fun newCompositionOnTheSamePlayerKeepsPlaying() {
        val run = PlayerRun()
        try {
            run.start(plainProject())
            run.awaitFrames(10, "first composition")
            run.start(withEffects(plainProject()))
            run.awaitFrames(run.frames.get() + 10, "second composition")
            run.start(plainProject())
            run.awaitFrames(run.frames.get() + 10, "third composition")
        } finally {
            run.release()
        }
    }

    @Test
    fun photoProjectPlays() = assertPlays(photoProject())

    @Test
    fun photoAndVideoWithEffectsPlays() {
        val photo = photoProject().timeline.findClip("photo")!!.second
        val project = plainProject()
        val main = project.timeline.findClip("main")!!.second
        assertPlays(withEffects(MainTrackEdits.withClips(Project("p", "test", 0, 0), listOf(main, photo.copy(startUs = main.endUs)))))
    }

    /** The player set up as before this fix, with Media3's experimental replayable frame cache. */
    @Test
    fun replayableCachePlayerShowsFrames() {
        val run = PlayerRun(replayableCache = true)
        try {
            run.start(plainProject())
            run.awaitFrames(15, "replayable cache playback")
        } finally {
            run.release()
        }
    }

    private fun assertPlays(project: Project) {
        val run = PlayerRun()
        try {
            run.start(project)
            run.awaitFrames(15, "playback")
            val pixel = run.lastPixel.get()
            val brightness = (Color.red(pixel) + Color.green(pixel) + Color.blue(pixel)) / 3
            assertTrue("Frame is black (pixel ${Integer.toHexString(pixel)})", brightness > 20)
        } finally {
            run.release()
        }
    }

    private fun plainProject(): Project {
        val clip = MediaClip(
            id = "main",
            startUs = 0,
            source = MediaSource(
                Uri.fromFile(video).toString(),
                MediaKind.VIDEO,
                MediaInfo(WIDTH, HEIGHT, frameRate = 30f, durationUs = DURATION_US, audioTrackCount = 1, audioMimeType = "audio/mp4a-latm"),
            ),
            trimStartUs = 0,
            trimEndUs = DURATION_US,
        )
        return MainTrackEdits.withClips(Project("p", "test", 0, 0), listOf(clip))
    }

    private fun photoProject(): Project {
        val clip = MediaClip(
            id = "photo",
            startUs = 0,
            source = MediaSource(Uri.fromFile(photo).toString(), MediaKind.IMAGE, MediaInfo(WIDTH, HEIGHT, durationUs = DURATION_US)),
            trimStartUs = 0,
            trimEndUs = DURATION_US,
        )
        return MainTrackEdits.withClips(Project("p", "test", 0, 0), listOf(clip))
    }

    private fun layered(project: Project): Project {
        val main = project.timeline.findClip("main")!!.second
        return OverlayEdits.add(project, main.copy(id = "overlay", transform = ClipTransform.OVERLAY_DEFAULT), "overlays")
    }

    private fun withEffects(project: Project): Project {
        val main = project.timeline.findClip("main")!!.second
        val withClipEffect = com.flurocup.core.model.edit.TimelineEdits.update(
            project,
            main.copy(effects = listOf(ClipEffect("clipfx", "gaussian_blur"))),
        )!!
        return EffectEdits.add(withClipEffect, EffectItem("trackfx", 0, DURATION_US, "vhs"), "effects")
    }

    /** One preview engine drawing into an image reader that counts frames. */
    private inner class PlayerRun(private val replayableCache: Boolean = false) {
        val frames = AtomicInteger()
        val lastPixel = AtomicReference(0)
        private val thread = HandlerThread("frames").apply { start() }
        private val reader = ImageReader.newInstance(WIDTH, HEIGHT, PixelFormat.RGBA_8888, 3).apply {
            setOnImageAvailableListener({ r ->
                val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    val plane = image.planes[0]
                    val offset = (HEIGHT / 2) * plane.rowStride + (WIDTH / 2) * plane.pixelStride
                    val b = plane.buffer
                    lastPixel.set(Color.rgb(b.get(offset).toInt() and 0xFF, b.get(offset + 1).toInt() and 0xFF, b.get(offset + 2).toInt() and 0xFF))
                    frames.incrementAndGet()
                } finally {
                    image.close()
                }
            }, Handler(thread.looper))
        }
        private val holder = ReaderHolder(reader.surface)
        private var engine: PreviewEngine? = null
        private var cachePlayer: androidx.media3.transformer.CompositionPlayer? = null

        fun start(project: Project) = onMain {
            val layered = builder.isLayered(project)
            val spec = RenderSpec(WIDTH, HEIGHT, 30f, uriFor = { it.source.uri }, lookFor = LiveLooks()::forClip)
            val composition = checkNotNull(builder.video(project, spec))
            if (replayableCache) {
                val p = androidx.media3.transformer.CompositionPlayer.Builder(context).experimentalSetEnableReplayableCache(true).build()
                cachePlayer = p
                p.setComposition(composition)
                p.setVideoSurfaceHolder(holder)
                p.prepare()
                p.play()
                return@onMain
            }
            val e = engine ?: PreviewEngine(context).also { engine = it }
            e.setComposition(composition, 0, layered)
            e.player.value!!.setVideoSurfaceHolder(holder)
            e.seekTo(0)
            e.play()
        }

        fun awaitFrames(count: Int, what: String) {
            val deadline = System.currentTimeMillis() + 30_000
            while (System.currentTimeMillis() < deadline) {
                val error = onMain { engine?.error?.value ?: cachePlayer?.playerError }
                if (error != null) throw AssertionError("$what: player error ${PreviewEngine.describe(error)}", error)
                if (frames.get() >= count) return
                Thread.sleep(50)
            }
            val state = onMain { engine?.player?.value?.let { "state=${it.playbackState} position=${it.currentPosition}" } }
            throw AssertionError("$what: only ${frames.get()} of $count frames in 30 s ($state)")
        }

        fun release() {
            onMain {
                engine?.release()
                cachePlayer?.release()
            }
            reader.close()
            thread.quitSafely()
        }
    }

    /** A SurfaceHolder over a plain Surface, which is what CompositionPlayer draws into. */
    private class ReaderHolder(private val surface: Surface) : SurfaceHolder {
        override fun addCallback(callback: SurfaceHolder.Callback?) = Unit
        override fun removeCallback(callback: SurfaceHolder.Callback?) = Unit
        override fun isCreating() = false
        @Deprecated("Deprecated in Java") override fun setType(type: Int) = Unit
        override fun setFixedSize(width: Int, height: Int) = Unit
        override fun setSizeFromLayout() = Unit
        override fun setFormat(format: Int) = Unit
        override fun setKeepScreenOn(screenOn: Boolean) = Unit
        override fun lockCanvas(): Canvas? = null
        override fun lockCanvas(dirty: Rect?): Canvas? = null
        override fun unlockCanvasAndPost(canvas: Canvas?) = Unit
        override fun getSurfaceFrame() = Rect(0, 0, WIDTH, HEIGHT)
        override fun getSurface() = surface
    }

    companion object {
        private const val TAG = "PreviewDeviceTest"
        private const val WIDTH = 320
        private const val HEIGHT = 240
        private const val DURATION_US = 2_000_000L
        private lateinit var video: File
        private lateinit var photo: File

        private fun <T> onMain(block: () -> T): T {
            var result: Result<T>? = null
            InstrumentationRegistry.getInstrumentation().runOnMainSync { result = runCatching(block) }
            return result!!.getOrThrow()
        }

        /** A two-second test video made from a bright picture, encoded on the device. */
        @JvmStatic
        @BeforeClass
        fun makeVideo() {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val png = File(context.cacheDir, "test_frame.png")
            val bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
            Canvas(bitmap).apply {
                drawColor(Color.rgb(255, 170, 60))
                drawRect(WIDTH / 2f, 0f, WIDTH.toFloat(), HEIGHT.toFloat(), Paint().apply { color = Color.rgb(60, 220, 200) })
            }
            png.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            photo = png
            video = File(context.cacheDir, "test_video.mp4").apply { delete() }
            val item = EditedMediaItem.Builder(MediaItem.Builder().setUri(Uri.fromFile(png)).setImageDurationMs(DURATION_US / 1000).build())
                .setFrameRate(30)
                .build()
            // With a silent sound track, like footage from a phone.
            val sequence = EditedMediaItemSequence.Builder(setOf(androidx.media3.common.C.TRACK_TYPE_AUDIO, androidx.media3.common.C.TRACK_TYPE_VIDEO))
                .addItem(item)
                .experimentalSetForceAudioTrack(true)
                .build()
            val composition = Composition.Builder(sequence).build()
            runBlocking { withContext(Dispatchers.Main) { runTransformer(context, composition, video.path, {}, {}) } }
            check(video.length() > 0) { "test video was not written" }
        }
    }
}
