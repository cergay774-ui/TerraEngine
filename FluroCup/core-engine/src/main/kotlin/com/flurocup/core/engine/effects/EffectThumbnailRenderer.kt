package com.flurocup.core.engine.effects

import android.graphics.Bitmap
import android.graphics.Matrix
import android.opengl.EGL14
import android.opengl.GLES20
import android.opengl.GLUtils
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.UnstableApi
import com.flurocup.core.model.EffectCatalog
import com.flurocup.core.model.EffectDefinition
import com.flurocup.core.model.EffectParamType
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext

/**
 * Draws small previews of effects on a picture (the frame under the playhead), with the same
 * shaders the preview and export use, for the tiles of the effect picker. Runs on its own GL
 * thread with an offscreen context.
 */
@OptIn(UnstableApi::class)
@Singleton
class EffectThumbnailRenderer @Inject constructor(
    private val library: EffectLibrary,
) {
    private val dispatcher = Executors.newSingleThreadExecutor { Thread(it, "EffectThumbnails") }.asCoroutineDispatcher()
    private val programs = HashMap<String, GlProgram?>()
    private var ready = false
    private var sourceTex = 0
    private var outputTex = 0
    private var fbo = 0
    private var sourceKey: Any? = null

    /**
     * Renders [definition] on [source] (already [WIDTH] x [HEIGHT]); [sourceKey] identifies the
     * picture so it is uploaded once for many effects. Null if the effect can't be drawn here.
     */
    suspend fun render(source: Bitmap, sourceKey: Any, definition: EffectDefinition): Bitmap? = withContext(dispatcher) {
        try {
            setUp()
            if (sourceKey != this@EffectThumbnailRenderer.sourceKey) {
                upload(source)
                this@EffectThumbnailRenderer.sourceKey = sourceKey
            }
            val program = programs.getOrPut(definition.id) {
                runCatching { createProgram(library.fragmentShader(definition)) }
                    .onFailure { Log.w(TAG, "No thumbnail for ${definition.id}", it) }
                    .getOrNull()
            } ?: return@withContext null
            draw(program, definition)
            readPixels()
        } catch (e: Exception) {
            Log.w(TAG, "Thumbnail failed for ${definition.id}", e)
            null
        }
    }

    private fun setUp() {
        if (ready) return
        val display = GlUtil.getDefaultEglDisplay()
        val context = GlUtil.createEglContext(display)
        GlUtil.createFocusedPlaceholderEglSurface(context, display)
        check(EGL14.eglGetCurrentContext() != EGL14.EGL_NO_CONTEXT)
        val ids = IntArray(2)
        GLES20.glGenTextures(2, ids, 0)
        sourceTex = ids[0]
        outputTex = ids[1]
        listOf(sourceTex, outputTex).forEach { tex ->
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, outputTex)
        GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, WIDTH, HEIGHT, 0, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null)
        val fbos = IntArray(1)
        GLES20.glGenFramebuffers(1, fbos, 0)
        fbo = fbos[0]
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo)
        GLES20.glFramebufferTexture2D(GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0, GLES20.GL_TEXTURE_2D, outputTex, 0)
        GlUtil.checkGlError()
        ready = true
    }

    /** GL textures start at the bottom row; the picture is flipped so effects see it upright. */
    private fun upload(source: Bitmap) {
        val flipped = Bitmap.createBitmap(source, 0, 0, source.width, source.height, Matrix().apply { preScale(1f, -1f) }, false)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, sourceTex)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, flipped, 0)
        if (flipped !== source) flipped.recycle()
        GlUtil.checkGlError()
    }

    private fun draw(program: GlProgram, definition: EffectDefinition) {
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo)
        GLES20.glViewport(0, 0, WIDTH, HEIGHT)
        program.use()
        program.setSamplerTexIdUniform("uTexSampler", sourceTex, 0)
        program.setFloatsUniformIfPresent("uSize", floatArrayOf(WIDTH.toFloat(), HEIGHT.toFloat()))
        program.setFloatsUniformIfPresent("uTimeSec", floatArrayOf(SAMPLE_TIME_S))
        program.setFloatsUniformIfPresent("uTime", floatArrayOf(SAMPLE_TIME_S))
        program.setFloatsUniformIfPresent("uProgress", floatArrayOf(SAMPLE_PROGRESS))
        program.setFloatsUniformIfPresent("uActive", floatArrayOf(1f))
        val values = definition.resolve(emptyMap())
        definition.params.forEach { param ->
            val value = values.getValue(param.id)
            val name = EffectCatalog.uniformName(param.id)
            val floats = if (param.type == EffectParamType.COLOR) {
                val rgb = value.toInt()
                floatArrayOf(((rgb shr 16) and 0xFF) / 255f, ((rgb shr 8) and 0xFF) / 255f, (rgb and 0xFF) / 255f)
            } else {
                floatArrayOf(value)
            }
            program.setFloatsUniformIfPresent(name, floats)
        }
        program.bindAttributesAndUniforms()
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GlUtil.checkGlError()
    }

    private fun readPixels(): Bitmap {
        val buffer = ByteBuffer.allocateDirect(WIDTH * HEIGHT * 4).order(ByteOrder.nativeOrder())
        GLES20.glReadPixels(0, 0, WIDTH, HEIGHT, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buffer)
        GlUtil.checkGlError()
        val upsideDown = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
        upsideDown.copyPixelsFromBuffer(buffer)
        // Rows come back bottom first.
        val upright = Bitmap.createBitmap(upsideDown, 0, 0, WIDTH, HEIGHT, Matrix().apply { preScale(1f, -1f) }, false)
        if (upright !== upsideDown) upsideDown.recycle()
        return upright
    }

    private fun createProgram(fragmentShader: String) = GlProgram(ShaderEffect.VERTEX_SHADER, fragmentShader).apply {
        setBufferAttribute("aFramePosition", GlUtil.getNormalizedCoordinateBounds(), GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE)
    }

    companion object {
        private const val TAG = "EffectThumbnails"
        const val WIDTH = 144
        const val HEIGHT = 108

        // A moment in the effect where flashes, shakes and zooms are visibly under way.
        private const val SAMPLE_TIME_S = 0.6f
        private const val SAMPLE_PROGRESS = 0.15f
    }
}
