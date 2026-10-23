vec4 effect(vec2 uv) {
  vec2 d = vec2(cos(radians(u_angle)), sin(radians(u_angle))) * 0.06 * u_amount;
  return directionalBlur(uv, d);
}
