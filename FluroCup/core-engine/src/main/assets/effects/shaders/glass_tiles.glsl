vec4 effect(vec2 uv) {
  vec2 cell = fract(uv * uSize / u_size) - 0.5;
  return tex(uv + cell * u_size * px() * 0.5 * u_amount);
}
