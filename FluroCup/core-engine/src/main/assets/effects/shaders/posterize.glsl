vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float n = floor(u_levels);
  c.rgb = floor(c.rgb * n + 0.5) / n;
  return c;
}
