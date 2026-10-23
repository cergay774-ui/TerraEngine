vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float d = length(toCentered(uv) - toCentered(vec2(u_x, u_y)));
  float k = smoothstep(u_size, u_size * 0.7, d);
  c.rgb *= mix(1.0 - u_intensity * 0.85, 1.0 + 0.15 * u_intensity, k);
  return c;
}
