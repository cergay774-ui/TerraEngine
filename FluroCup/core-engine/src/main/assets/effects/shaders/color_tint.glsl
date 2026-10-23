vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, u_color * luma(c.rgb) * 1.6, u_intensity);
  return c;
}
