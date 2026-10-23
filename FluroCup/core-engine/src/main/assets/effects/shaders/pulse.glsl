vec4 effect(vec2 uv) {
  float s = 1.0 + 0.08 * u_amount * (0.5 + 0.5 * sin(uTime * TAU * u_speed));
  return tex(transformUv(uv, s, 0.0, vec2(0.0)));
}
