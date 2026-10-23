vec4 effect(vec2 uv) {
  float t = uTime * u_speed * 0.6;
  vec2 p = toCentered(uv);
  float a = smoothstep(1.0, 0.0, length(p - vec2(-0.7 + 0.4 * sin(t), 0.3 * cos(t * 1.3))));
  float b = smoothstep(0.9, 0.0, length(p - vec2(0.7 * cos(t * 0.7), -0.4 + 0.3 * sin(t))));
  vec3 leak = u_color * a + mix(u_color, vec3(1.0, 0.9, 0.55), 0.5) * b * 0.8;
  vec4 c = tex(uv);
  c.rgb = screen(c.rgb, leak * u_intensity);
  return c;
}
