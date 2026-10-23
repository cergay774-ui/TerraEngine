vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = (uv - 0.5) * vec2(aspect(), 1.0);
  float d = -sdBox(p, vec2(aspect(), 1.0) * 0.5);
  float a = atan(p.y, p.x) / TAU;
  vec3 col = hsv2rgb(vec3(fract(a + uTime * 0.3 * u_speed), 0.7, 1.0));
  c.rgb = mix(c.rgb, col, step(d, u_width));
  return c;
}
