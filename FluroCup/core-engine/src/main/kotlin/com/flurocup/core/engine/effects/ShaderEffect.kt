package com.flurocup.core.engine.effects

import android.content.Context
import android.opengl.GLES20
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram

/**
 * Base for FluroCup's GLSL effects: a fragment shader drawn over the whole frame, with uniforms
 * set per frame by [setUniforms]. Every shader gets `uTexSampler` (the input frame),
 * `vTexSamplingCoord` (0..1, origin bottom-left), `uSize` (frame size in pixels) and `uTimeSec`.
 *
 * New effects are one fragment shader plus a uniform setter; the frame size never changes.
 */
@OptIn(UnstableApi::class)
abstract class ShaderEffect : GlEffect {

    /** GLSL ES 1.00 fragment shader source. */
    protected abstract val fragmentShader: String

    /** Sets this effect's uniforms for the frame at [presentationTimeUs]. Called on the GL thread. */
    protected abstract fun setUniforms(program: UniformSetter, presentationTimeUs: Long)

    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        Program(useHdr, fragmentShader, ::setUniforms)

    /** Safe uniform access: uniforms the GLSL compiler optimised away are skipped, not fatal. */
    class UniformSetter internal constructor(private val program: GlProgram) {
        fun float(name: String, value: Float) = program.setFloatsUniformIfPresent(name, floatArrayOf(value))
        fun vec2(name: String, x: Float, y: Float) = program.setFloatsUniformIfPresent(name, floatArrayOf(x, y))
        fun vec3(name: String, x: Float, y: Float, z: Float) = program.setFloatsUniformIfPresent(name, floatArrayOf(x, y, z))
        fun vec4(name: String, x: Float, y: Float, z: Float, w: Float) =
            program.setFloatsUniformIfPresent(name, floatArrayOf(x, y, z, w))

        /** An ARGB colour as a vec4 (r, g, b, a). */
        fun color(name: String, argb: Long) = vec4(
            name,
            ((argb shr 16) and 0xFF) / 255f,
            ((argb shr 8) and 0xFF) / 255f,
            (argb and 0xFF) / 255f,
            ((argb shr 24) and 0xFF) / 255f,
        )
    }

    private class Program(
        useHdr: Boolean,
        fragmentShader: String,
        private val uniforms: (UniformSetter, Long) -> Unit,
    ) : BaseGlShaderProgram(useHdr, /* texturePoolCapacity= */ 1) {

        private val program: GlProgram = try {
            createProgram(fragmentShader)
        } catch (e: GlUtil.GlException) {
            // A shader this GPU can't compile must not take the whole preview or export down:
            // the effect is skipped and the frame passes through.
            Log.e(TAG, "Effect shader failed to compile; passing frames through", e)
            try {
                createProgram(PASSTHROUGH_SHADER)
            } catch (e2: GlUtil.GlException) {
                throw VideoFrameProcessingException(e2)
            }
        }
        private val setter = UniformSetter(program)
        private var width = 0
        private var height = 0

        override fun configure(inputWidth: Int, inputHeight: Int): Size {
            width = inputWidth
            height = inputHeight
            return Size(inputWidth, inputHeight)
        }

        override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
            try {
                program.use()
                program.setSamplerTexIdUniform("uTexSampler", inputTexId, /* texUnitIndex= */ 0)
                setter.vec2("uSize", width.toFloat(), height.toFloat())
                setter.float("uTimeSec", presentationTimeUs / 1_000_000f)
                uniforms(setter, presentationTimeUs)
                program.bindAttributesAndUniforms()
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                GlUtil.checkGlError()
            } catch (e: GlUtil.GlException) {
                throw VideoFrameProcessingException(e, presentationTimeUs)
            }
        }

        override fun release() {
            super.release()
            try {
                program.delete()
            } catch (e: GlUtil.GlException) {
                throw VideoFrameProcessingException(e)
            }
        }
    }

    companion object {
        private const val TAG = "ShaderEffect"

        private fun createProgram(fragmentShader: String) = GlProgram(VERTEX_SHADER, fragmentShader).apply {
            setBufferAttribute(
                "aFramePosition",
                GlUtil.getNormalizedCoordinateBounds(),
                GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
            )
        }

        const val PASSTHROUGH_SHADER = """precision mediump float;
uniform sampler2D uTexSampler;
varying vec2 vTexSamplingCoord;
void main() {
  gl_FragColor = texture2D(uTexSampler, vTexSamplingCoord);
}
"""

        const val VERTEX_SHADER = """
attribute vec4 aFramePosition;
varying vec2 vTexSamplingCoord;
void main() {
  gl_Position = aFramePosition;
  vTexSamplingCoord = aFramePosition.xy * 0.5 + 0.5;
}
"""
    }
}
