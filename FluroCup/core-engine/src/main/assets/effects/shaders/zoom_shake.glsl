vec4 effect(vec2 uv) {
  float t = uTime * 10.0 * u_speed;
  vec2 o = (vec2(noise(vec2(t, 1.0)), noise(vec2(t, 5.0))) - 0.5) * 0.05 * u_intensity;
  float zoom = 1.05 + 0.1 * u_intensity * (0.5 + 0.5 * sin(t * 0.8));
  return tex(transformUv(uv, zoom, 0.0, o));
}
