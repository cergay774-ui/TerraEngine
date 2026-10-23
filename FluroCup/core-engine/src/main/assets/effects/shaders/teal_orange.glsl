vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float l = luma(c.rgb);
  vec3 grade = mix(vec3(0.0, 0.35, 0.45), vec3(1.0, 0.6, 0.3), smoothstep(0.2, 0.8, l));
  vec3 g = clamp(c.rgb + (grade - 0.5) * 0.35, 0.0, 1.0);
  c.rgb = mix(c.rgb, g, u_intensity);
  return c;
}
