vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  c.rgb = clamp(mix(vec3(luma(c.rgb)), c.rgb, u_amount), 0.0, 1.0);
  return c;
}
