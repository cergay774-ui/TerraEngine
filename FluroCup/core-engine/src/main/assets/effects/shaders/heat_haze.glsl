vec4 effect(vec2 uv) {
  float t = uTime * u_speed;
  float n = noise(vec2(uv.x * 30.0, uv.y * 12.0 - t * 4.0));
  return tex(uv + vec2(0.0, (n - 0.5) * 0.012 * u_amount));
}
