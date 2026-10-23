vec4 effect(vec2 uv) {
  vec2 p = toCentered(uv);
  float a = sin(uTime * 4.0 * u_speed) * u_amount * 1.5 * max(0.6 - length(p), 0.0);
  return tex(fromCentered(rotate2(p, a)));
}
