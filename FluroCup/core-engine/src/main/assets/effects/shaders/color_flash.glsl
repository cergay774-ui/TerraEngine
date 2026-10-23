vec4 effect(vec2 uv) {
  float f = pow(max(1.0 - uProgress / u_fade, 0.0), 2.0) * u_intensity;
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, screen(c.rgb, u_color), f);
  return c;
}
