vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = toCentered(uv);
  float r = length(p);
  float ring = smoothstep(0.004, 0.0, abs(r - u_size));
  float lines = max(step(abs(p.x), 0.002), step(abs(p.y), 0.002)) * step(r, u_size * 1.5) * step(u_size * 0.3, r);
  float dotC = fill(r - 0.006, 0.002);
  c.rgb = mix(c.rgb, u_color, max(max(ring, lines), dotC) * u_intensity);
  return c;
}
