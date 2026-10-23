vec4 effect(vec2 uv) {
  vec2 c = toCentered(vec2(u_x, u_y));
  vec2 p = toCentered(uv) - c;
  float d = length(p) / u_radius;
  if (d < 1.0) p *= mix(1.0, smoothstep(0.0, 1.0, d), u_amount);
  return tex(fromCentered(p + c));
}
