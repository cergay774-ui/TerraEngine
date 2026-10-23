vec4 effect(vec2 uv) {
  vec2 inner = vec2(0.06, 0.18);
  vec2 q = (uv - vec2(inner.x * 0.6, inner.y)) / vec2(1.0 - inner.x * 1.2, 1.0 - inner.y - 0.05);
  bool inside = q.x > 0.0 && q.x < 1.0 && q.y > 0.0 && q.y < 1.0;
  if (inside) return tex(q);
  return vec4(u_color * (0.96 + 0.04 * noise(uv * uSize / 4.0)), 1.0);
}
