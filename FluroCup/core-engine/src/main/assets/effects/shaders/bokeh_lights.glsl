vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = toCentered(uv) * 3.0;
  vec3 acc = vec3(0.0);
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 cell = floor(p + vec2(uTime * 0.1 * u_speed, 0.0)) + vec2(float(i), float(j));
      vec2 h = hash22(cell);
      vec2 pos = cell + h - vec2(uTime * 0.1 * u_speed, 0.0);
      float r = 0.2 + h.y * 0.3;
      float m = fill(length(p - pos) - r, 0.04) * (0.25 + 0.15 * h.x);
      acc += hsv2rgb(vec3(0.05 + h.x * 0.15, 0.6, 1.0)) * m;
    }
  }
  c.rgb = screen(c.rgb, acc * u_intensity);
  return c;
}
