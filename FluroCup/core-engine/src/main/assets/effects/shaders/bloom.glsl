vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec3 glow = vec3(0.0);
  for (int i = 0; i < 16; i++) {
    float a = float(i) * 2.3999632;
    float r = sqrt((float(i) + 0.5) / 16.0) * u_radius;
    vec3 s = tex(uv + vec2(cos(a), sin(a)) * r * px()).rgb;
    glow += max(s - u_threshold, 0.0);
  }
  c.rgb += glow / 16.0 * 3.0 * u_intensity;
  return vec4(clamp(c.rgb, 0.0, 1.0), tex(uv).a);
}
