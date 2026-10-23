vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float n = fbm(uv * 3.0 + vec2(uTime * 0.3 * u_speed, 0.0));
  float edge = length(toCentered(uv)) * 0.9 + n * 0.6;
  float burn = smoothstep(0.75, 0.95, edge + u_intensity * 0.2 - 0.1);
  vec3 glow = vec3(1.0, 0.45, 0.1) * smoothstep(0.0, 0.08, burn) * (1.0 - smoothstep(0.08, 0.3, burn));
  c.rgb = mix(c.rgb, vec3(0.02, 0.01, 0.0), smoothstep(0.25, 0.5, burn) * u_intensity);
  c.rgb = screen(c.rgb, glow * 2.0 * u_intensity);
  return c;
}
