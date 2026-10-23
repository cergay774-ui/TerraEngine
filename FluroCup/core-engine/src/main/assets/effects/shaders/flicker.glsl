vec4 effect(vec2 uv) {
  float n = noise(vec2(uTime * 12.0 * u_speed, 3.0));
  vec4 c = tex(uv);
  c.rgb *= 1.0 - u_intensity * 0.6 * n;
  return c;
}
