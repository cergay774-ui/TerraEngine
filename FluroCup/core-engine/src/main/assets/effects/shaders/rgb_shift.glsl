vec4 effect(vec2 uv) {
  vec2 d = vec2(cos(radians(u_angle)), sin(radians(u_angle))) * 0.02 * u_amount;
  return vec4(tex(uv + d).r, tex(uv).g, tex(uv - d).b, tex(uv).a);
}
