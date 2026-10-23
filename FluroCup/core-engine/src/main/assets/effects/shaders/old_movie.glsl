vec4 effect(vec2 uv) {
  float t = floor(uTime * 16.0);
  vec4 c = tex(uv + vec2(0.0, (hash11(t) - 0.5) * 0.004));
  float l = luma(c.rgb);
  vec3 bw = vec3(l) * vec3(1.0, 0.95, 0.85);
  bw *= 0.9 + 0.1 * hash11(t * 3.0);
  float scratch = step(0.75, hash11(t + 2.0)) * smoothstep(1.2, 0.0, abs(uv.x - hash11(t + 9.0)) * uSize.x);
  bw = mix(bw, vec3(0.85), scratch);
  bw += (hash21(uv * uSize + t) - 0.5) * 0.15;
  bw *= 1.0 - smoothstep(0.3, 0.8, length(toCentered(uv))) * 0.8;
  c.rgb = mix(c.rgb, clamp(bw, 0.0, 1.0), u_intensity);
  return c;
}
