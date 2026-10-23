vec4 effect(vec2 uv) {
  float phase = fract(uTime * u_bpm / 60.0);
  float f = exp(-phase * 8.0) * u_intensity;
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, screen(c.rgb, u_color), f);
  return c;
}
