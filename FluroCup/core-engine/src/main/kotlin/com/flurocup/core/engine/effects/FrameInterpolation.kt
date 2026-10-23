package com.flurocup.core.engine.effects

import android.content.Context
import android.opengl.GLES20
import androidx.annotation.OptIn
import androidx.media3.common.GlObjectsProvider
import androidx.media3.common.GlTextureInfo
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import com.flurocup.core.model.export.OutputFrameClock
import java.util.ArrayDeque
import java.util.concurrent.Executor
import kotlin.math.max

/**
 * Raises the frame rate of an export to [fps] by making frames between the source ones.
 *
 * With [smooth] the new frames are motion-compensated: the movement between two source frames
 * is estimated on the GPU (block matching on a 1/8-size picture, the "optical flow"), and each
 * new frame is both neighbours moved part of the way along it and blended. Where the estimate is
 * unsure (flat areas, things appearing) it falls back to a plain cross-fade. Without [smooth]
 * source frames are repeated, which gives a file at that rate with the original motion.
 *
 * Use it as the last effect of an export; it does nothing for frames already at the rate.
 */
@OptIn(UnstableApi::class)
class FrameInterpolationEffect(fps: Float, private val smooth: Boolean) : GlEffect {

    // Media3 makes a new shader program for each clip; sharing the clock keeps one even grid
    // of output frames across cuts.
    private val clock = OutputFrameClock(fps)

    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        FrameInterpolationShaderProgram(useHdr, smooth, clock)
}

@OptIn(UnstableApi::class)
private class FrameInterpolationShaderProgram(
    private val useHdr: Boolean,
    private val smooth: Boolean,
    private val clock: OutputFrameClock,
) : GlShaderProgram {

    /** One input frame and the output times still to be made from it. */
    private class Job(val input: GlTextureInfo, val inputUs: Long, val previousUs: Long, val blend: Boolean, val times: List<Long>) {
        var next = 0
    }

    private var inputListener: GlShaderProgram.InputListener = object : GlShaderProgram.InputListener {}
    private var outputListener: GlShaderProgram.OutputListener = object : GlShaderProgram.OutputListener {}
    private var errorListener: GlShaderProgram.ErrorListener = GlShaderProgram.ErrorListener { }
    private var errorExecutor: Executor = Executor { it.run() }

    private val copyProgram = program(COPY_SHADER)
    private val interpolateProgram = program(INTERPOLATE_SHADER)
    private val downsampleProgram = if (smooth) program(DOWNSAMPLE_SHADER) else null
    private val flowProgram = if (smooth) program(FLOW_SHADER) else null
    private val smoothFlowProgram = if (smooth) program(SMOOTH_FLOW_SHADER) else null

    private val freeOutputs = ArrayDeque<GlTextureInfo>()
    private val usedOutputs = ArrayList<GlTextureInfo>()
    private var previous: GlTextureInfo? = null
    private var previousSmall: GlTextureInfo? = null
    private var currentSmall: GlTextureInfo? = null
    private var rawFlow: GlTextureInfo? = null
    private var flow: GlTextureInfo? = null
    private var width = 0
    private var height = 0
    private var hasPrevious = false
    private var job: Job? = null
    private var endPending = false

    override fun setInputListener(inputListener: GlShaderProgram.InputListener) {
        this.inputListener = inputListener
        if (job == null) inputListener.onReadyToAcceptInputFrame()
    }

    override fun setOutputListener(outputListener: GlShaderProgram.OutputListener) {
        this.outputListener = outputListener
    }

    override fun setErrorListener(executor: Executor, errorListener: GlShaderProgram.ErrorListener) {
        errorExecutor = executor
        this.errorListener = errorListener
    }

    override fun queueInputFrame(glObjectsProvider: GlObjectsProvider, inputTexture: GlTextureInfo, presentationTimeUs: Long) {
        try {
            ensureConfigured(glObjectsProvider, inputTexture.width, inputTexture.height)
            val previousUs = clock.lastInputUs
            val times = clock.plan(presentationTimeUs)
            val blend = hasPrevious && !clock.restarted
            if (smooth) {
                draw(downsampleProgram!!, currentSmall!!) {
                    it.setSamplerTexIdUniform("uTex", inputTexture.texId, 0)
                    it.setFloatsUniform("uStep", floatArrayOf(2f / width, 2f / height))
                }
                if (blend) estimateFlow()
            }
            job = Job(inputTexture, presentationTimeUs, previousUs, blend, times)
            drain()
        } catch (e: Exception) {
            fail(e)
        }
    }

    override fun releaseOutputFrame(outputTexture: GlTextureInfo) {
        if (!usedOutputs.remove(outputTexture)) return
        freeOutputs.add(outputTexture)
        try {
            drain()
        } catch (e: Exception) {
            fail(e)
        }
    }

    override fun signalEndOfCurrentInputStream() {
        // The next stream starts with a new shot: don't blend across the cut.
        hasPrevious = false
        if (job != null) endPending = true else outputListener.onCurrentOutputStreamEnded()
    }

    override fun flush() {
        job = null
        endPending = false
        hasPrevious = false
        clock.reset()
        freeOutputs.addAll(usedOutputs)
        usedOutputs.clear()
        inputListener.onFlush()
        inputListener.onReadyToAcceptInputFrame()
    }

    override fun release() {
        try {
            (freeOutputs + usedOutputs).forEach { it.release() }
            freeOutputs.clear()
            usedOutputs.clear()
            listOfNotNull(previous, previousSmall, currentSmall, rawFlow, flow).forEach { it.release() }
            listOfNotNull(copyProgram, interpolateProgram, downsampleProgram, flowProgram, smoothFlowProgram).forEach { it.delete() }
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e)
        }
    }

    /** Makes the current job's output frames while there are free textures to draw them in. */
    private fun drain() {
        val current = job ?: return
        while (current.next < current.times.size) {
            val output = freeOutputs.pollFirst() ?: return
            usedOutputs.add(output)
            val timeUs = current.times[current.next]
            if (current.blend && timeUs < current.inputUs) {
                val alpha = (timeUs - current.previousUs).toFloat() / max(1L, current.inputUs - current.previousUs)
                draw(interpolateProgram, output) {
                    it.setSamplerTexIdUniform("uPrev", previous!!.texId, 0)
                    it.setSamplerTexIdUniform("uCur", current.input.texId, 1)
                    it.setSamplerTexIdUniform("uFlow", (flow ?: previous!!).texId, 2)
                    it.setFloatUniform("uAlpha", alpha.coerceIn(0f, 1f))
                    it.setFloatUniform("uUseFlow", if (smooth) 1f else 0f)
                    it.setFloatUniform("uRepeat", if (smooth) 0f else 1f)
                    val small = currentSmall
                    it.setFloatsUniform(
                        "uFlowRange",
                        if (small != null) floatArrayOf(SEARCH_RADIUS / small.width, SEARCH_RADIUS / small.height) else floatArrayOf(0f, 0f),
                    )
                }
            } else {
                draw(copyProgram, output) { it.setSamplerTexIdUniform("uTex", current.input.texId, 0) }
            }
            current.next++
            outputListener.onOutputFrameAvailable(output, timeUs)
        }
        // Every frame from this input is out: keep it as the frame before the next one.
        draw(copyProgram, previous!!) { it.setSamplerTexIdUniform("uTex", current.input.texId, 0) }
        hasPrevious = true
        if (smooth) {
            val swap = previousSmall
            previousSmall = currentSmall
            currentSmall = swap
        }
        job = null
        inputListener.onInputFrameProcessed(current.input)
        if (endPending) {
            endPending = false
            outputListener.onCurrentOutputStreamEnded()
        }
        inputListener.onReadyToAcceptInputFrame()
    }

    /** Movement from the previous small picture to the current one, then smoothed. */
    private fun estimateFlow() {
        val small = currentSmall!!
        draw(flowProgram!!, rawFlow!!) {
            it.setSamplerTexIdUniform("uPrevSmall", previousSmall!!.texId, 0)
            it.setSamplerTexIdUniform("uCurSmall", small.texId, 1)
            it.setFloatsUniform("uTexel", floatArrayOf(1f / small.width, 1f / small.height))
        }
        draw(smoothFlowProgram!!, flow!!) {
            it.setSamplerTexIdUniform("uFlow", rawFlow!!.texId, 0)
            it.setFloatsUniform("uTexel", floatArrayOf(1f / small.width, 1f / small.height))
        }
    }

    private fun ensureConfigured(provider: GlObjectsProvider, w: Int, h: Int) {
        if (w == width && h == height && previous != null) return
        (freeOutputs + usedOutputs).forEach { it.release() }
        freeOutputs.clear()
        usedOutputs.clear()
        listOfNotNull(previous, previousSmall, currentSmall, rawFlow, flow).forEach { it.release() }
        width = w
        height = h
        hasPrevious = false
        repeat(OUTPUT_CAPACITY) { freeOutputs.add(texture(provider, w, h, useHdr)) }
        previous = texture(provider, w, h, useHdr)
        if (smooth) {
            val sw = max(MIN_SMALL, w / SMALL_FACTOR)
            val sh = max(MIN_SMALL, h / SMALL_FACTOR)
            previousSmall = texture(provider, sw, sh, false)
            currentSmall = texture(provider, sw, sh, false)
            rawFlow = texture(provider, sw, sh, false)
            flow = texture(provider, sw, sh, false)
        }
    }

    private inline fun draw(program: GlProgram, target: GlTextureInfo, setUniforms: (GlProgram) -> Unit) {
        GlUtil.focusFramebufferUsingCurrentContext(target.fboId, target.width, target.height)
        program.use()
        setUniforms(program)
        program.bindAttributesAndUniforms()
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GlUtil.checkGlError()
    }

    private fun fail(e: Exception) {
        errorExecutor.execute { errorListener.onError(VideoFrameProcessingException.from(e)) }
    }

    private companion object {
        const val OUTPUT_CAPACITY = 3
        const val SMALL_FACTOR = 8
        const val MIN_SMALL = 16
        /** Largest encoded offset in small pixels: the +-6 search plus the sub-pixel refinement. */
        const val SEARCH_RADIUS = 7f

        fun texture(provider: GlObjectsProvider, w: Int, h: Int, highPrecision: Boolean): GlTextureInfo =
            provider.createBuffersForTexture(GlUtil.createTexture(w, h, highPrecision), w, h)

        fun program(fragment: String) = GlProgram(ShaderEffect.VERTEX_SHADER, fragment).apply {
            setBufferAttribute("aFramePosition", GlUtil.getNormalizedCoordinateBounds(), GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE)
        }

        const val COPY_SHADER = """precision highp float;
uniform sampler2D uTex;
varying vec2 vTexSamplingCoord;
void main() {
  gl_FragColor = texture2D(uTex, vTexSamplingCoord);
}
"""

        /** Luma at 1/8 size: 16 bilinear taps, each averaging 2x2 pixels, cover an 8x8 block. */
        const val DOWNSAMPLE_SHADER = """precision highp float;
uniform sampler2D uTex;
uniform vec2 uStep;
varying vec2 vTexSamplingCoord;
void main() {
  float s = 0.0;
  for (int j = 0; j < 4; j++) {
    for (int i = 0; i < 4; i++) {
      vec2 o = (vec2(float(i), float(j)) - 1.5) * uStep;
      s += dot(texture2D(uTex, vTexSamplingCoord + o).rgb, vec3(0.299, 0.587, 0.114));
    }
  }
  s /= 16.0;
  gl_FragColor = vec4(s, s, s, 1.0);
}
"""

        /**
         * Block matching: for each small pixel, the offset within +-6 small pixels where a 3x3
         * patch of the previous picture best matches the current one, refined to a fraction of a
         * pixel by fitting a parabola through the neighbouring costs. Encoded as rg = offset / 7
         * mapped to 0..1, b = how textured the patch is (flat patches can't tell motion),
         * a = how good the match is.
         */
        const val FLOW_SHADER = """precision highp float;
uniform sampler2D uPrevSmall;
uniform sampler2D uCurSmall;
uniform vec2 uTexel;
varying vec2 vTexSamplingCoord;
float cost(vec2 uv, vec2 d, vec2 t) {
  float c = 0.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 o = vec2(float(i), float(j)) * t;
      c += abs(texture2D(uPrevSmall, uv + o).r - texture2D(uCurSmall, uv + o + d * t).r);
    }
  }
  return c;
}
void main() {
  vec2 uv = vTexSamplingCoord;
  vec2 t = uTexel;
  float best = 1.0e9;
  vec2 bestD = vec2(0.0);
  for (int j = -6; j <= 6; j++) {
    for (int i = -6; i <= 6; i++) {
      vec2 d = vec2(float(i), float(j));
      // A slight preference for less movement keeps still areas still.
      float c = cost(uv, d, t) + 0.01 * length(d);
      if (c < best) {
        best = c;
        bestD = d;
      }
    }
  }
  float c0 = cost(uv, bestD, t);
  float cl = cost(uv, bestD - vec2(1.0, 0.0), t);
  float cr = cost(uv, bestD + vec2(1.0, 0.0), t);
  float cd = cost(uv, bestD - vec2(0.0, 1.0), t);
  float cu = cost(uv, bestD + vec2(0.0, 1.0), t);
  float dx = cl - 2.0 * c0 + cr;
  float dy = cd - 2.0 * c0 + cu;
  vec2 sub = vec2(dx > 1.0e-4 ? 0.5 * (cl - cr) / dx : 0.0, dy > 1.0e-4 ? 0.5 * (cd - cu) / dy : 0.0);
  vec2 motion = bestD + clamp(sub, -0.5, 0.5);
  float mean = 0.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      mean += texture2D(uPrevSmall, uv + vec2(float(i), float(j)) * t).r;
    }
  }
  mean /= 9.0;
  float detail = 0.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      detail += abs(texture2D(uPrevSmall, uv + vec2(float(i), float(j)) * t).r - mean);
    }
  }
  float textured = clamp(detail * 6.0, 0.0, 1.0);
  float quality = 1.0 - smoothstep(0.08, 0.35, best);
  gl_FragColor = vec4(motion / 7.0 * 0.5 + 0.5, textured, quality);
}
"""

        /**
         * 5x5 average of the flow weighted by how textured and well matched each patch is, so the
         * motion found at an object's edges also moves its flat inside, and lone wrong matches
         * fade out. a = the match quality around, which decides how much to trust the motion.
         */
        const val SMOOTH_FLOW_SHADER = """precision highp float;
uniform sampler2D uFlow;
uniform vec2 uTexel;
varying vec2 vTexSamplingCoord;
void main() {
  vec2 sum = vec2(0.0);
  float weights = 0.0;
  float quality = 0.0;
  for (int j = -2; j <= 2; j++) {
    for (int i = -2; i <= 2; i++) {
      vec4 f = texture2D(uFlow, vTexSamplingCoord + vec2(float(i), float(j)) * uTexel);
      float w = (f.b + 0.01) * (f.a + 0.01);
      sum += f.rg * w;
      weights += w;
      quality += f.a;
    }
  }
  gl_FragColor = vec4(sum / weights, 1.0, quality / 25.0);
}
"""

        /**
         * A frame [uAlpha] of the way from the previous frame to the current one: both moved
         * along the flow towards that moment and blended; a cross-fade where the flow is unsure.
         * With [uRepeat] the previous frame is shown as it is.
         */
        const val INTERPOLATE_SHADER = """precision highp float;
uniform sampler2D uPrev;
uniform sampler2D uCur;
uniform sampler2D uFlow;
uniform float uAlpha;
uniform float uUseFlow;
uniform float uRepeat;
uniform vec2 uFlowRange;
varying vec2 vTexSamplingCoord;
void main() {
  vec2 uv = vTexSamplingCoord;
  vec4 prev = texture2D(uPrev, uv);
  if (uRepeat > 0.5) {
    gl_FragColor = prev;
    return;
  }
  vec4 blended = mix(prev, texture2D(uCur, uv), uAlpha);
  if (uUseFlow < 0.5) {
    gl_FragColor = blended;
    return;
  }
  vec4 f = texture2D(uFlow, uv);
  vec2 d = (f.rg * 2.0 - 1.0) * uFlowRange;
  vec4 a = texture2D(uPrev, clamp(uv - d * uAlpha, 0.0, 1.0));
  vec4 b = texture2D(uCur, clamp(uv + d * (1.0 - uAlpha), 0.0, 1.0));
  gl_FragColor = mix(blended, mix(a, b, uAlpha), smoothstep(0.2, 0.7, f.a));
}
"""
    }
}
