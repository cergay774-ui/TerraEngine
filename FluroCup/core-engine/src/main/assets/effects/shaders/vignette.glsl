vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float v = smoothstep(u_size * 0.5, u_size * 0.5 + 0.5, length(toCentered(uv)));
  c.rgb = mix(c.rgb, u_color, v * u_intensity);
  return c;
}
