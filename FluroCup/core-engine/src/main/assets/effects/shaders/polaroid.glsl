vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec3 g = c.rgb * vec3(1.05, 1.0, 0.92) + vec3(0.06, 0.05, 0.08);
  g = mix(g, vec3(luma(g)), 0.15);
  g = mix(g, g * g * (3.0 - 2.0 * g), 0.3);
  g *= 1.0 - 0.3 * smoothstep(0.4, 0.9, length(toCentered(uv)));
  c.rgb = mix(c.rgb, clamp(g, 0.0, 1.0), u_intensity);
  return c;
}
