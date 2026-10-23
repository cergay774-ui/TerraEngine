vec4 effect(vec2 uv) {
  vec2 p = toCentered(uv);
  float d = length(p) / u_radius;
  if (d < 1.0) p *= mix(1.0, pow(max(d, 1e-4), -0.5 * u_amount), 1.0 - d);
  return tex(fromCentered(p));
}
