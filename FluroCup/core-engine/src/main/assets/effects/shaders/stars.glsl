vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = toCentered(uv) * 6.0;
  vec2 cell = floor(p);
  vec2 h = hash22(cell);
  vec2 pos = cell + 0.3 + h * 0.4;
  float pulse = 0.5 + 0.5 * sin(uTime * 3.0 * u_speed + h.x * 20.0);
  vec2 d = rotate2(p - pos, uTime * (h.y - 0.5) * 2.0) / (0.15 + 0.1 * pulse);
  float m = step(0.6, h.y) * fill(sdStarShape(d, 1.0, 0.45), 0.05);
  float glow = step(0.6, h.y) * exp(-length(p - pos) * 5.0) * 0.4 * pulse;
  c.rgb = mix(c.rgb, u_color, m * u_intensity);
  c.rgb = screen(c.rgb, u_color * glow * u_intensity);
  return c;
}
