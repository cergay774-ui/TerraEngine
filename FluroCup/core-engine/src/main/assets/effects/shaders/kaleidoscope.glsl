vec4 effect(vec2 uv) {
  vec2 p = toCentered(uv);
  float a = atan(p.y, p.x) + uTime * u_speed * 0.5;
  float seg = TAU / floor(u_segments);
  a = mod(a, seg);
  a = abs(a - seg * 0.5);
  return tex(fromCentered(vec2(cos(a), sin(a)) * length(p)));
}
