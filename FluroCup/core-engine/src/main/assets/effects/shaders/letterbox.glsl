vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float bar = step(uv.y, u_amount) + step(1.0 - u_amount, uv.y);
  c.rgb = mix(c.rgb, u_color, clamp(bar, 0.0, 1.0));
  return c;
}
