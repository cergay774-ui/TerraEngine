vec4 effect(vec2 uv) {
  float d = length(toCentered(uv) - toCentered(vec2(u_x, u_y))) / u_size;
  vec3 halo = u_color * (exp(-d * 3.0) + 0.3 * smoothstep(0.1, 0.0, abs(d - 0.7)));
  vec4 c = tex(uv);
  c.rgb = screen(c.rgb, halo * u_intensity);
  return c;
}
