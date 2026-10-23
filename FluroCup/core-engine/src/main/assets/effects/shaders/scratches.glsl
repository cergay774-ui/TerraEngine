vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float t = floor(uTime * 18.0);
  float s = 0.0;
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float x = hash11(t * 1.3 + fi * 11.0);
    float on = step(0.6, hash11(t + fi * 5.0));
    s += on * smoothstep(1.5, 0.0, abs(uv.x - x) * uSize.x) * (0.6 + 0.4 * noise(vec2(uv.y * 20.0, t)));
  }
  c.rgb = mix(c.rgb, vec3(0.9), clamp(s, 0.0, 1.0) * u_intensity);
  return c;
}
