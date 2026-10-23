vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, 1.0 - c.rgb, u_intensity);
  return c;
}
