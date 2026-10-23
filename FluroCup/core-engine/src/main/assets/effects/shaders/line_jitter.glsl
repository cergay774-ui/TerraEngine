vec4 effect(vec2 uv) {
  float t = floor(uTime * 20.0 * max(u_speed, 0.05));
  float row = floor(uv.y * uSize.y / 3.0);
  float off = (hash21(vec2(row, t)) - 0.5) * 0.03 * u_intensity * step(0.6, hash21(vec2(t, floor(row / 20.0))));
  return tex(uv + vec2(off, 0.0));
}
