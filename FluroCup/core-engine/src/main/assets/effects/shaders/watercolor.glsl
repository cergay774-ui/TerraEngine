vec4 effect(vec2 uv) {
  vec2 w = (vec2(fbm(uv * 8.0), fbm(uv * 8.0 + 3.7)) - 0.5) * 0.01;
  vec4 b = discBlur(uv + w, 5.0);
  vec3 q = floor(b.rgb * 6.0 + 0.5) / 6.0;
  float paper = 0.92 + 0.08 * fbm(uv * uSize / 40.0);
  vec3 s = mix(q, vec3(1.0), 0.12) * paper;
  s *= 1.0 - 0.3 * smoothstep(0.2, 0.6, sobel(uv, 2.0));
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, s, u_intensity);
  return c;
}
