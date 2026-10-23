vec4 effect(vec2 uv) {
  float k = exp(-uProgress * 7.0) * u_intensity;
  vec2 o = vec2(sin(uTime * 90.0), cos(uTime * 77.0)) * 0.03 * k;
  return tex(transformUv(uv, 1.0 + 0.18 * k, 0.0, o));
}
