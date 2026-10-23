vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 g = fract(uv * floor(u_lines));
  vec2 w = floor(u_lines) * 1.2 * px();
  float m = max(step(g.x, w.x), step(g.y, w.y));
  c.rgb = mix(c.rgb, u_color, m * u_opacity);
  return c;
}
