vec4 effect(vec2 uv) {
  float e = clamp(sobel(uv, 1.0) * u_strength, 0.0, 1.0);
  return vec4(u_color * e, tex(uv).a);
}
