vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec4 best = c;
  for (int i = 1; i <= 14; i++) {
    vec4 s = tex(uv + vec2(0.0, float(i) * 0.008 * u_length));
    if (luma(s.rgb) > u_threshold && luma(s.rgb) > luma(best.rgb)) best = s;
  }
  return luma(c.rgb) > u_threshold ? c : mix(c, best, 0.85);
}
