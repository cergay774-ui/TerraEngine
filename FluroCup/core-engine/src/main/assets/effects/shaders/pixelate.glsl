vec4 effect(vec2 uv) {
  vec2 cell = u_size * px();
  return tex((floor(uv / cell) + 0.5) * cell);
}
