vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float g = hash21(floor(uv * uSize / u_size) + fract(uTime * 24.0) * 97.0) - 0.5;
  c.rgb = clamp(c.rgb + g * 0.25 * u_intensity * (1.0 - luma(c.rgb) * 0.5), 0.0, 1.0);
  return c;
}
