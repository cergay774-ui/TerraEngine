vec4 effect(vec2 uv) {
  float a = uTime * TAU * 0.25 * u_speed;
  return tex(transformUv(uv, 1.8, a, vec2(0.0)));
}
