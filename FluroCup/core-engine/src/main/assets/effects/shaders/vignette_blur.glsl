vec4 effect(vec2 uv) {
  float k = smoothstep(u_size * 0.5, u_size * 0.5 + 0.35, length(toCentered(uv)));
  return discBlur(uv, u_radius * k);
}
