vec4 effect(vec2 uv) {
  float f = exp(-uProgress * 10.0) * u_intensity;
  vec4 c = tex(uv);
  vec3 over = clamp(c.rgb * (1.0 + 4.0 * f) + f * 0.6, 0.0, 1.0);
  float vig = 1.0 - 0.4 * f * length(toCentered(uv));
  c.rgb = over * vig;
  return c;
}
