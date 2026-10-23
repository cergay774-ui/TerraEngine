vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = toCentered(uv) * 10.0;
  vec2 q = p + vec2(fbm(p * 0.2 + uTime * 0.1) * 2.0, uTime * 0.3 * u_speed);
  vec2 cell = floor(q);
  vec2 h = hash22(cell);
  vec2 pos = cell + 0.2 + h * 0.6;
  float m = step(0.5, h.y) * exp(-length(q - pos) * 14.0) * (0.5 + 0.5 * sin(uTime * 2.0 + h.x * 20.0));
  c.rgb = screen(c.rgb, vec3(1.0, 0.92, 0.75) * m * u_intensity * 1.5);
  return c;
}
