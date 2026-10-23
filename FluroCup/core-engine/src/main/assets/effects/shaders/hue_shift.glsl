vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec3 h = rgb2hsv(c.rgb);
  h.x = fract(h.x + u_shift / 360.0 + uTime * u_cycle * 0.25);
  c.rgb = hsv2rgb(h);
  return c;
}
