vec4 effect(vec2 uv) {
  float beat = uTime * u_bpm / 60.0;
  float k = exp(-fract(beat) * 6.0) * u_intensity;
  vec2 dir = normalize(hash22(vec2(floor(beat), 3.0)) - 0.5 + 0.001);
  return tex(transformUv(uv, 1.0 + 0.08 * k, 0.0, dir * 0.04 * k));
}
