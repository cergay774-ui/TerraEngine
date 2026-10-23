vec4 effect(vec2 uv) {
  vec2 c = vec2(u_x, u_y);
  vec2 p = toCentered(uv) - toCentered(c);
  float a = 0.25 * u_amount * clamp(length(p) * 2.0, 0.0, 1.0);
  vec4 acc = vec4(0.0);
  for (int i = 0; i < 16; i++) {
    float t = (float(i) / 15.0 - 0.5) * a;
    acc += tex(fromCentered(rotate2(p, t) + toCentered(c)));
  }
  return acc / 16.0;
}
