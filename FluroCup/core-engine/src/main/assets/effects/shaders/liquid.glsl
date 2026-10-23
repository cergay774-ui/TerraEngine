vec4 effect(vec2 uv) {
  float t = uTime * u_speed;
  vec2 q = vec2(fbm(uv * 3.0 + t), fbm(uv * 3.0 + vec2(5.2, 1.3) - t));
  return tex(uv + (q - 0.5) * 0.08 * u_amount);
}
