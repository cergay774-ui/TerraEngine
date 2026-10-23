vec4 effect(vec2 uv) {
  vec2 p = toCentered(uv) - toCentered(vec2(u_x, u_y));
  float r = length(p) / u_size;
  float ring = smoothstep(0.12, 0.0, abs(r - 1.0));
  vec3 rainbow = hsv2rgb(vec3(clamp((r - 0.88) / 0.24, 0.0, 1.0), 0.8, 1.0));
  vec4 c = tex(uv);
  c.rgb = screen(c.rgb, rainbow * ring * 0.6 * u_intensity);
  return c;
}
