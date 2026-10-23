vec4 effect(vec2 uv) {
  float t = uTime * 14.0 * u_speed;
  vec2 o = (vec2(noise(vec2(t, 1.0)), noise(vec2(t, 7.0))) - 0.5) * 0.09 * u_intensity;
  float a = (noise(vec2(t, 13.0)) - 0.5) * 0.08 * u_intensity;
  return tex(transformUv(uv, 1.0 + 0.12 * u_intensity, a, o));
}
