vec4 effect(vec2 uv) {
  float a = radians(u_angle) * sin(uTime * TAU * 0.5 * u_speed);
  return tex(transformUv(uv, 1.0 + abs(sin(radians(u_angle))) * 1.2, a, vec2(0.0)));
}
