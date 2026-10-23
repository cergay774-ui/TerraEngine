vec4 effect(vec2 uv) {
  float t = uTime * 8.0 * u_speed;
  vec2 o = (vec2(noise(vec2(t, 1.0)), noise(vec2(t, 7.0))) - 0.5) * 0.03 * u_intensity;
  return tex(transformUv(uv, 1.0 + 0.04 * u_intensity, 0.0, o));
}
