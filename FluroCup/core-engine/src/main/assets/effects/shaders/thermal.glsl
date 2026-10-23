vec3 thermalRamp(float t) {
  vec3 a = vec3(0.0, 0.0, 0.3);
  vec3 b = vec3(0.6, 0.0, 0.7);
  vec3 c = vec3(1.0, 0.3, 0.0);
  vec3 d = vec3(1.0, 1.0, 0.3);
  if (t < 0.33) return mix(a, b, t / 0.33);
  if (t < 0.66) return mix(b, c, (t - 0.33) / 0.33);
  return mix(c, d, (t - 0.66) / 0.34);
}
vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, thermalRamp(luma(c.rgb)), u_intensity);
  return c;
}
