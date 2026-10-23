vec4 effect(vec2 uv) {
  float t = uTime * u_speed;
  vec2 o = (vec2(fbm(vec2(t, 0.0)), fbm(vec2(0.0, t))) - 0.5) * 0.04 * u_intensity;
  float a = (fbm(vec2(t * 0.7, 4.0)) - 0.5) * 0.03 * u_intensity;
  return tex(transformUv(uv, 1.0 + 0.05 * u_intensity, a, o));
}
