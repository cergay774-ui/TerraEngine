vec4 effect(vec2 uv) {
  float n = floor(u_count + 0.5);
  return tex(fract(uv * n));
}
