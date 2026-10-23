vec4 effect(vec2 uv) {
  vec4 acc = vec4(0.0);
  float w = 0.0;
  for (int i = 0; i < 32; i++) {
    float a = float(i) * 2.3999632;
    float r = sqrt((float(i) + 0.5) / 32.0);
    float k = exp(-r * r * 2.0);
    acc += tex(uv + vec2(cos(a), sin(a)) * r * u_radius * px()) * k;
    w += k;
  }
  return acc / w;
}
