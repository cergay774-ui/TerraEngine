vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = uv * uSize / 10.0;
  vec2 cell = floor(p);
  vec2 h = hash22(cell);
  float on = step(1.0 - 0.3 * u_density, h.x);
  float tw = pow(0.5 + 0.5 * sin(uTime * 6.0 + h.y * 40.0), 8.0);
  vec2 f = fract(p) - 0.5;
  float star = max(exp(-abs(f.x) * 20.0) * exp(-abs(f.y) * 3.0), exp(-abs(f.y) * 20.0) * exp(-abs(f.x) * 3.0));
  float l = luma(c.rgb);
  c.rgb = screen(c.rgb, vec3(1.0, 0.95, 0.85) * star * tw * on * u_intensity * (0.4 + l));
  return c;
}
