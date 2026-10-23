vec4 effect(vec2 uv) {
  return tex(transformUv(uv, 1.0 + 0.35 * u_amount * uProgress, 0.0, vec2(0.0)));
}
