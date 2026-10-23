vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec4 b = discBlur(uv, 10.0);
  c.rgb = mix(c.rgb, screen(c.rgb, b.rgb * 0.6), u_intensity);
  return c;
}
