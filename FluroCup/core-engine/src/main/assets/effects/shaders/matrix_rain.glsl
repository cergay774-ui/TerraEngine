vec4 effect(vec2 uv) {
  vec2 grid = vec2(uSize.x / 14.0, uSize.y / 18.0);
  vec2 cell = floor(uv * grid);
  float speed = 0.5 + hash11(cell.x) * 1.5;
  float head = fract(-uTime * speed * 0.3 * u_speed + hash11(cell.x * 7.0));
  float trail = fract(cell.y / grid.y - head);
  float glyph = step(0.5, hash21(cell + floor(uTime * 8.0 * u_speed + hash11(cell.y))));
  vec2 f = fract(uv * grid);
  float shape = glyph * step(0.15, f.x) * step(f.x, 0.85) * step(0.1, f.y) * step(f.y, 0.9) * step(0.5, hash21(floor(f * 4.0) + cell));
  float bright = pow(1.0 - trail, 6.0) * shape;
  vec4 c = tex(uv);
  vec3 m = c.rgb * vec3(0.1, 0.35, 0.1) + vec3(0.3, 1.0, 0.4) * bright;
  c.rgb = mix(c.rgb, clamp(m, 0.0, 1.0), u_intensity);
  return c;
}
