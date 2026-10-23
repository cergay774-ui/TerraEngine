vec4 effect(vec2 uv) {
  vec3 acc = vec3(0.0);
  float w = 0.0;
  for (int i = 0; i < 40; i++) {
    float a = float(i) * 2.3999632;
    float r = sqrt((float(i) + 0.5) / 40.0);
    vec3 s = tex(uv + vec2(cos(a), sin(a)) * r * u_radius * px()).rgb;
    float k = 1.0 + pow(luma(s), 4.0) * 8.0 * u_highlights;
    acc += s * k;
    w += k;
  }
  return vec4(acc / w, tex(uv).a);
}
