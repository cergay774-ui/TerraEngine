package com.flurocup.core.engine.effects

import com.flurocup.core.model.ClipLook
import com.flurocup.core.model.MaskShape
import java.util.concurrent.atomic.AtomicReference

/**
 * Per-clip look in one shader pass, on the clip's own (cropped) picture: chroma key, mask,
 * rounded corners, border and opacity. Reads [look] every frame, so the preview can change it
 * live without being rebuilt.
 */
class ClipLookEffect(private val look: AtomicReference<ClipLook>) : ShaderEffect() {

    override val fragmentShader: String = SHADER

    override fun setUniforms(program: UniformSetter, presentationTimeUs: Long) {
        val current = look.get()
        program.float("uOpacity", current.opacity.coerceIn(0f, 1f))

        val key = current.chromaKey
        program.float("uChromaOn", if (key != null) 1f else 0f)
        if (key != null) {
            program.color("uKeyColor", key.colorArgb)
            // Distances are in Cb/Cr space, where colours lie within about 0.7 of each other.
            program.float("uSimilarity", key.similarity.coerceIn(0f, 1f) * 0.4f)
            program.float("uSmoothness", key.smoothness.coerceIn(0f, 1f) * 0.25f + 0.005f)
            program.float("uSpill", key.spill.coerceIn(0f, 1f))
        }

        val mask = current.mask
        program.float("uMaskShape", mask?.shape?.let { MASK_CODES.getValue(it) } ?: 0f)
        if (mask != null) {
            // Model y runs down from the top; GL texture y runs up from the bottom.
            program.vec2("uMaskCenter", mask.centerX, 1f - mask.centerY)
            program.vec2("uMaskHalfSize", (mask.width / 2f).coerceAtLeast(0.001f), (mask.height / 2f).coerceAtLeast(0.001f))
            program.float("uMaskRotation", Math.toRadians(mask.rotation.toDouble()).toFloat())
            program.float("uMaskFeather", mask.feather.coerceIn(0f, 0.5f))
            program.float("uMaskRadius", mask.cornerRadius.coerceIn(0f, 1f))
            program.float("uMaskInvert", if (mask.invert) 1f else 0f)
        }

        program.float("uCornerRadius", current.cornerRadius.coerceIn(0f, 0.5f))
        program.float("uBorderWidth", current.border.width.coerceIn(0f, 0.2f))
        program.color("uBorderColor", current.border.colorArgb)
    }

    private companion object {
        val MASK_CODES = mapOf(
            MaskShape.LINEAR to 1f,
            MaskShape.MIRROR to 2f,
            MaskShape.CIRCLE to 3f,
            MaskShape.RECTANGLE to 4f,
            MaskShape.HEART to 5f,
            MaskShape.STAR to 6f,
        )

        const val SHADER = """
precision highp float;
uniform sampler2D uTexSampler;
varying vec2 vTexSamplingCoord;
uniform vec2 uSize;
uniform float uOpacity;

uniform float uChromaOn;
uniform vec4 uKeyColor;
uniform float uSimilarity;
uniform float uSmoothness;
uniform float uSpill;

uniform float uMaskShape;
uniform vec2 uMaskCenter;
uniform vec2 uMaskHalfSize;
uniform float uMaskRotation;
uniform float uMaskFeather;
uniform float uMaskRadius;
uniform float uMaskInvert;

uniform float uCornerRadius;
uniform float uBorderWidth;
uniform vec4 uBorderColor;

vec2 chroma(vec3 c) {
  return vec2(
      -0.168736 * c.r - 0.331264 * c.g + 0.5 * c.b,
      0.5 * c.r - 0.418688 * c.g - 0.081312 * c.b);
}

float dot2(vec2 v) { return dot(v, v); }

float sdRoundBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sdHeart(vec2 p) {
  p.x = abs(p.x);
  if (p.y + p.x > 1.0) return sqrt(dot2(p - vec2(0.25, 0.75))) - 0.35355339;
  return sqrt(min(dot2(p - vec2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

float sdStar5(vec2 p, float r, float rf) {
  vec2 k1 = vec2(0.809016994375, -0.587785252292);
  vec2 k2 = vec2(-k1.x, k1.y);
  p.x = abs(p.x);
  p -= 2.0 * max(dot(k1, p), 0.0) * k1;
  p -= 2.0 * max(dot(k2, p), 0.0) * k2;
  p.x = abs(p.x);
  p.y -= r;
  vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
  float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
  return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// Signed distance in pixels from the mask's edge; negative inside.
float maskDistance(vec2 px) {
  vec2 center = uMaskCenter * uSize;
  vec2 halfSz = uMaskHalfSize * uSize;
  float c = cos(uMaskRotation);
  float s = sin(uMaskRotation);
  vec2 d = px - center;
  // Clockwise rotation on screen is clockwise here too, since y points up.
  vec2 p = vec2(c * d.x - s * d.y, s * d.x + c * d.y);
  float m = min(halfSz.x, halfSz.y);
  if (uMaskShape < 1.5) return p.y;
  if (uMaskShape < 2.5) return abs(p.y) - halfSz.y;
  if (uMaskShape < 3.5) return (length(p / halfSz) - 1.0) * m;
  if (uMaskShape < 4.5) return sdRoundBox(p, halfSz, uMaskRadius * m);
  if (uMaskShape < 5.5) {
    vec2 q = vec2(p.x / halfSz.x * 0.62, p.y / halfSz.y * 0.55 + 0.45);
    return sdHeart(q) * m * 1.6;
  }
  return sdStar5(p / m, 0.95, 0.45) * m;
}

void main() {
  vec4 color = texture2D(uTexSampler, vTexSamplingCoord);
  vec2 px = vTexSamplingCoord * uSize;
  float alpha = 1.0;

  if (uChromaOn > 0.5) {
    vec2 c = chroma(color.rgb);
    vec2 keyC = chroma(uKeyColor.rgb);
    float dist = distance(c, keyC);
    alpha *= smoothstep(uSimilarity, uSimilarity + uSmoothness, dist);
    // Spill: remove the part of the pixel's colour that points towards the key colour, keeping
    // its brightness, so green fringes and reflections turn neutral instead of grey.
    float keyLen = length(keyC);
    if (keyLen > 0.001 && uSpill > 0.0) {
      vec2 dir = keyC / keyLen;
      float along = max(dot(c, dir), 0.0);
      vec2 cleaned = c - dir * along * uSpill;
      float y = dot(color.rgb, vec3(0.299, 0.587, 0.114));
      color.rgb = clamp(vec3(
          y + 1.402 * cleaned.y,
          y - 0.344136 * cleaned.x - 0.714136 * cleaned.y,
          y + 1.772 * cleaned.x), 0.0, 1.0);
    }
  }

  if (uMaskShape > 0.5) {
    float feather = max(1.0, uMaskFeather * min(uSize.x, uSize.y));
    float inside = 1.0 - smoothstep(-feather, feather, maskDistance(px));
    alpha *= mix(inside, 1.0 - inside, uMaskInvert);
  }

  float radius = uCornerRadius * min(uSize.x, uSize.y);
  float edge = sdRoundBox(px - uSize * 0.5, uSize * 0.5, radius);
  if (radius > 0.0) alpha *= 1.0 - smoothstep(-1.0, 0.0, edge);
  float border = uBorderWidth * min(uSize.x, uSize.y);
  if (border > 0.0) {
    float onBorder = smoothstep(-border - 1.0, -border, edge);
    color.rgb = mix(color.rgb, uBorderColor.rgb, onBorder * uBorderColor.a);
    alpha = max(alpha, onBorder * step(edge, 0.0));
  }

  gl_FragColor = vec4(color.rgb, color.a * alpha * uOpacity);
}
"""
    }
}
