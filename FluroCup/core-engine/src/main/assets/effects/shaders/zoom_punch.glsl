vec4 effect(vec2 uv) {
  float k = exp(-uProgress * 6.0);
  return tex(transformUv(uv, 1.0 + 0.4 * u_intensity * k, 0.0, vec2(0.0)));
}
