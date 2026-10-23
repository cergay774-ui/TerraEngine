vec4 effect(vec2 uv) {
  float p = smoothstep(0.0, 1.0, uProgress);
  float s = 1.1 + 0.4 * u_zoom * p;
  vec2 o = vec2(u_pan_x, u_pan_y) * 0.06 * (p - 0.5);
  return tex(transformUv(uv, s, 0.0, o));
}
