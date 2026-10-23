vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, mix(u_dark, u_light, smoothstep(0.05, 0.95, luma(c.rgb))), u_intensity);
  return c;
}
