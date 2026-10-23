vec4 effect(vec2 uv) {
  vec2 p = toCentered(uv) - toCentered(vec2(u_x, u_y));
  float d = length(p);
  float w = sin(d * 40.0 - uTime * 8.0 * u_speed) * 0.012 * u_amount * exp(-d * 2.0);
  return tex(fromCentered(toCentered(uv) + normalize(p + 1e-5) * w));
}
