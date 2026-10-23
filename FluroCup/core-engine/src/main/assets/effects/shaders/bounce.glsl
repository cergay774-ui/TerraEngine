vec4 effect(vec2 uv) {
  float b = abs(sin(uTime * PI * u_speed));
  vec2 o = vec2(0.0, b * 0.05 * u_amount);
  vec2 p = uv - 0.5;
  p.y /= 1.0 - 0.06 * u_amount * (1.0 - b);
  return tex(transformUv(p + 0.5, 1.08 + 0.05 * u_amount, 0.0, o));
}
