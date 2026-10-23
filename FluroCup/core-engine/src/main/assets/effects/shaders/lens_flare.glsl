vec4 effect(vec2 uv) {
  vec2 p = toCentered(uv);
  vec2 sun = toCentered(vec2(u_x, u_y));
  float glow = 0.02 / (length(p - sun) + 0.02);
  vec3 flare = u_color * glow * 0.6;
  for (int i = 1; i <= 5; i++) {
    float k = float(i) * 0.35;
    vec2 ghost = sun - sun * k * 1.4;
    float r = 0.02 + 0.015 * float(i);
    flare += mix(u_color, vec3(0.5, 0.8, 1.0), float(i) / 5.0) * smoothstep(r, r * 0.6, length(p - ghost)) * 0.25;
  }
  flare += u_color * smoothstep(0.004, 0.0, abs((p - sun).y)) * 0.3 * smoothstep(0.8, 0.0, abs((p - sun).x));
  vec4 c = tex(uv);
  c.rgb = screen(c.rgb, flare * u_intensity);
  return c;
}
