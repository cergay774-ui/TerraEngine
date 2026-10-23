vec4 effect(vec2 uv) {
  vec2 o = px() * 1.5;
  float e = luma(tex(uv + o).rgb) - luma(tex(uv - o).rgb);
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, vec3(0.5 + e * 2.0), u_intensity);
  return c;
}
