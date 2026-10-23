vec4 effect(vec2 uv) {
  vec2 p = toCentered(uv) * 5.0;
  vec2 q = p - vec2(0.0, -uTime * 0.6 * u_speed);
  vec2 cell = floor(q);
  vec2 h = hash22(cell);
  vec2 pos = cell + 0.3 + h * 0.4 + vec2(sin(uTime * 2.0 + h.y * 10.0) * 0.1, 0.0);
  float r = 0.12 + h.x * 0.15;
  float d = length(q - pos);
  float on = step(0.5, h.y);
  float rim = on * smoothstep(0.03, 0.0, abs(d - r));
  float inside = on * step(d, r);
  vec2 refr = (q - pos) * inside * 0.02;
  vec4 c = tex(uv - refr * u_intensity);
  float spec = on * exp(-length(q - pos - vec2(-r, r) * 0.45) * 30.0);
  c.rgb = screen(c.rgb, vec3(0.8, 0.95, 1.0) * (rim * 0.6 + spec) * u_intensity);
  return c;
}
