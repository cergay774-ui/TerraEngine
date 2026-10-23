vec4 effect(vec2 uv) {
  vec2 o = (hash22(floor(uv * uSize)) - 0.5) * 18.0 * u_amount * px();
  vec4 c = discBlur(uv + o, 6.0 * u_amount);
  c.rgb = mix(c.rgb, vec3(1.0), 0.08 * u_amount);
  return c;
}
