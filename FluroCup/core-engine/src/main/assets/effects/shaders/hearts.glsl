vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = toCentered(uv) * 5.0;
  vec2 q = p - vec2(0.0, uTime * 0.8 * u_speed);
  vec2 cell = floor(q);
  vec2 h = hash22(cell);
  vec2 pos = cell + 0.3 + h * 0.4;
  float s = 0.18 + h.x * 0.12;
  vec2 d = (q - pos) / s;
  d.x += sin(uTime * 2.0 + h.y * 10.0) * 0.3;
  float m = step(0.55, h.y) * fill(sdHeartShape(d + vec2(0.0, 0.5)), 0.05);
  c.rgb = mix(c.rgb, u_color, m * u_intensity);
  return c;
}
