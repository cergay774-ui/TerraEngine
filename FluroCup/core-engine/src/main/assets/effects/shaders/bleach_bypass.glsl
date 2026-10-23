vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float l = luma(c.rgb);
  vec3 blend = vec3(l);
  vec3 overlay = mix(2.0 * c.rgb * blend, 1.0 - 2.0 * (1.0 - c.rgb) * (1.0 - blend), step(0.5, blend));
  c.rgb = mix(c.rgb, clamp(overlay, 0.0, 1.0), u_intensity);
  return c;
}
