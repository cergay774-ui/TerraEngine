vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec3 h = rgb2hsv(c.rgb);
  float target = rgb2hsv(u_color).x;
  float d = abs(h.x - target);
  d = min(d, 1.0 - d);
  float keep = (1.0 - smoothstep(u_range, u_range * 1.5, d)) * smoothstep(0.1, 0.25, h.y);
  c.rgb = mix(vec3(luma(c.rgb)), c.rgb, keep);
  return c;
}
