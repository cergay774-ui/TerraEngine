vec4 effect(vec2 uv) {
  vec2 d = (uv - 0.5) * 0.04 * u_amount;
  return vec4(tex(uv + d).r, tex(uv).g, tex(uv - d).b, tex(uv).a);
}
