vec4 effect(vec2 uv) {
  vec2 o = vec2(sin(uv.y * u_frequency + uTime * 3.0 * u_speed), cos(uv.x * u_frequency + uTime * 2.0 * u_speed)) * 0.015 * u_amount;
  return tex(uv + o);
}
