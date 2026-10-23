vec4 effect(vec2 uv) {
  vec2 source = vec2(u_x, u_y);
  vec2 delta = (uv - source) * u_length * 0.04;
  vec2 p = uv;
  vec3 rays = vec3(0.0);
  float decay = 1.0;
  for (int i = 0; i < 24; i++) {
    p -= delta;
    vec3 s = tex(p).rgb;
    rays += max(s - 0.55, 0.0) * decay;
    decay *= 0.94;
  }
  vec4 c = tex(uv);
  c.rgb += rays * 0.25 * u_intensity;
  return vec4(clamp(c.rgb, 0.0, 1.0), tex(uv).a);
}
