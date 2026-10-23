vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  c.rgb = clamp((c.rgb - 0.5) * u_amount + 0.5, 0.0, 1.0);
  return c;
}
