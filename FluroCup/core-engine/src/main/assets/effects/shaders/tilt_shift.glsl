vec4 effect(vec2 uv) {
  float k = smoothstep(u_width * 0.5, u_width * 0.5 + 0.25, abs(uv.y - u_focus));
  vec4 c = discBlur(uv, u_radius * k);
  c.rgb = mix(c.rgb, c.rgb * 1.1, 0.5);
  return c;
}
