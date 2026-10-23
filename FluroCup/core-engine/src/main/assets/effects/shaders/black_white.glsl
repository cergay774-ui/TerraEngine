vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float l = clamp((luma(c.rgb) - 0.5) * u_contrast + 0.5, 0.0, 1.0);
  c.rgb = mix(c.rgb, vec3(l), u_intensity);
  return c;
}
