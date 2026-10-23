vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = (uv - 0.5) * uSize;
  vec2 h = uSize * 0.5 - 40.0;
  vec2 a = abs(p);
  float corner = step(h.x - 60.0, a.x) * step(h.y - 60.0, a.y) * step(a.x, h.x) * step(a.y, h.y);
  float edge = max(step(h.x - 3.0, a.x) * step(a.x, h.x), step(h.y - 3.0, a.y) * step(a.y, h.y));
  float cross = max(step(abs(p.x), 1.5) * step(abs(p.y), 18.0), step(abs(p.y), 1.5) * step(abs(p.x), 18.0));
  float m = max(corner * edge, cross);
  c.rgb = mix(c.rgb, u_color, m * u_intensity);
  return c;
}
