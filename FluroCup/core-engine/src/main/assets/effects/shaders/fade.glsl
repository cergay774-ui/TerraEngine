vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec3 f = c.rgb * 0.8 + 0.12;
  f = mix(f, vec3(luma(f)), 0.3);
  c.rgb = mix(c.rgb, f, u_intensity);
  return c;
}
