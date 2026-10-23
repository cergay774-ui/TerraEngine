vec4 effect(vec2 uv) {
  vec2 cellPx = vec2(u_size);
  vec2 cell = floor(uv * uSize / cellPx);
  float l = luma(tex((cell + 0.5) * cellPx * px()).rgb);
  vec2 f = fract(uv * uSize / cellPx) - 0.5;
  float d = fill(length(f) - 0.45 * l, 0.06);
  return vec4(u_color * d, tex(uv).a);
}
