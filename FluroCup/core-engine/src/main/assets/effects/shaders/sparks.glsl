vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = toCentered(uv) * 8.0;
  float acc = 0.0;
  for (int layer = 0; layer < 2; layer++) {
    float fl = float(layer);
    vec2 q = p + vec2(0.0, uTime * (1.5 + fl) * u_speed);
    vec2 cell = floor(q);
    vec2 h = hash22(cell + fl * 31.0);
    vec2 pos = cell + 0.2 + h * 0.6;
    float tw = 0.5 + 0.5 * sin(uTime * 10.0 + h.x * 30.0);
    acc += step(0.6, h.y) * fill(length(q - pos) - 0.04, 0.05) * tw;
    acc += step(0.6, h.y) * exp(-length(q - pos) * 9.0) * 0.6 * tw;
  }
  c.rgb = screen(c.rgb, u_color * acc * u_intensity);
  return c;
}
