package com.flurocup.core.engine.effects

/**
 * Lays the finished frame over the project's background colour and makes it opaque. Without
 * this, areas a mask, chroma key or opacity made transparent would show the clip's original
 * colours on screen and in the file, because displays and encoders ignore alpha.
 */
class BackgroundFillEffect(private val colorArgb: Long) : ShaderEffect() {

    override val fragmentShader: String = """
precision mediump float;
uniform sampler2D uTexSampler;
varying vec2 vTexSamplingCoord;
uniform vec4 uBackground;
void main() {
  vec4 c = texture2D(uTexSampler, vTexSamplingCoord);
  gl_FragColor = vec4(mix(uBackground.rgb, c.rgb, c.a), 1.0);
}
"""

    override fun setUniforms(program: UniformSetter, presentationTimeUs: Long) {
        program.color("uBackground", colorArgb)
    }
}
