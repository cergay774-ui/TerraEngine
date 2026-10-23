vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = (uv - 0.5) * vec2(aspect(), 1.0);
  vec2 b = vec2(aspect(), 1.0) * (0.5 - u_inset);
  float d = sdBox(p, b - u_radius) - u_radius;
  c.rgb = mix(c.rgb, u_color, smoothstep(-0.002, 0.002, d));
  return c;
}
