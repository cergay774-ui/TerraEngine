vec4 effect(vec2 uv) {
  vec2 p = toCentered(uv);
  float d = length(p);
  float k = max(1.0 - d / u_radius, 0.0);
  return tex(fromCentered(rotate2(p, u_angle * k * k)));
}
