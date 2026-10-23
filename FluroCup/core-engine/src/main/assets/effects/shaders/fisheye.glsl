vec4 effect(vec2 uv) {
  vec2 p = toCentered(uv);
  float d = length(p);
  float k = 1.0 + u_amount * (d * d * 2.0 - 0.3);
  return tex(fromCentered(p * k / (1.0 + u_amount * 0.2)));
}
