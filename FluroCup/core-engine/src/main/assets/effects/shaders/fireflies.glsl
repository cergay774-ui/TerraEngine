vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = toCentered(uv) * 6.0;
  float acc = 0.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 cell = floor(p) + vec2(float(i), float(j));
      vec2 h = hash22(cell);
      float t = uTime * u_speed;
      vec2 pos = cell + 0.5 + 0.4 * vec2(sin(t + h.x * 20.0), cos(t * 0.8 + h.y * 20.0));
      float blink = smoothstep(0.3, 1.0, sin(t * 2.0 + h.x * 30.0));
      acc += step(0.4, h.y) * exp(-length(p - pos) * 10.0) * blink;
    }
  }
  c.rgb = screen(c.rgb, u_color * acc * 1.5 * u_intensity);
  return c;
}
