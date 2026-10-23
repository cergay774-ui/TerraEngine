vec4 effect(vec2 uv) {
  float t = floor(uTime * 12.0 * max(u_speed, 0.05));
  float band = floor(uv.y * 24.0);
  float on = step(1.0 - 0.4 * u_intensity, hash21(vec2(band, t)));
  vec2 off = vec2((hash21(vec2(t, band + 7.0)) - 0.5) * 0.2 * u_intensity * on, 0.0);
  float split = 0.012 * u_intensity * on;
  vec4 c = tex(uv + off);
  c.r = tex(uv + off + vec2(split, 0.0)).r;
  c.b = tex(uv + off - vec2(split, 0.0)).b;
  return c;
}
