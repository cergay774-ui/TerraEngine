vec4 effect(vec2 uv) {
  float t = uTime * u_speed;
  vec2 o = vec2(sin(t * 37.0) * 0.6 + sin(t * 23.0) * 0.4, sin(t * 51.0) * 0.5 + sin(t * 17.0) * 0.5) * 0.03 * u_intensity;
  o.y += step(0.8, noise(vec2(t * 3.0, 2.0))) * 0.04 * u_intensity;
  return tex(transformUv(uv, 1.0 + 0.1 * u_intensity, 0.0, o));
}
