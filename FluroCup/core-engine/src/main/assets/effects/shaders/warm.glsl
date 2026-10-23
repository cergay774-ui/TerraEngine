vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  c.rgb = clamp(c.rgb * vec3(1.0 + 0.15 * u_intensity, 1.0 + 0.03 * u_intensity, 1.0 - 0.15 * u_intensity), 0.0, 1.0);
  return c;
}
