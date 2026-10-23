vec4 effect(vec2 uv) {
  float t = uTime;
  vec2 jitter = vec2(0.0, (hash11(floor(t * 18.0)) - 0.5) * 0.006 * u_intensity);
  vec4 c = tex(uv + jitter);
  c.rgb = mix(c.rgb, c.rgb * vec3(1.08, 0.98, 0.8) + vec3(0.04, 0.02, 0.0), u_intensity);
  c.rgb += (hash21(uv * uSize + floor(t * 24.0)) - 0.5) * 0.18 * u_intensity;
  c.rgb *= 1.0 - 0.08 * u_intensity * hash11(floor(t * 24.0));
  float v = smoothstep(0.35, 0.85, length(toCentered(uv)));
  c.rgb *= 1.0 - v * 0.7 * u_intensity;
  return vec4(clamp(c.rgb, 0.0, 1.0), tex(uv).a);
}
