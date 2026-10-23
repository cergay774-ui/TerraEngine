vec4 effect(vec2 uv) {
  vec2 c = vec2(u_x, u_y);
  vec4 acc = vec4(0.0);
  for (int i = 0; i < 16; i++) {
    float s = 1.0 - 0.2 * u_amount * float(i) / 15.0;
    acc += tex(c + (uv - c) * s);
  }
  return acc / 16.0;
}
