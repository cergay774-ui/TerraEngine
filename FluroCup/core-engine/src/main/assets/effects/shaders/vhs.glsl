vec4 effect(vec2 uv) {
  float t = uTime * u_speed;
  float wobble = (noise(vec2(uv.y * 40.0, t * 3.0)) - 0.5) * 0.006 * u_intensity;
  float track = smoothstep(0.03, 0.0, abs(fract(uv.y + t * 0.12) - 0.5));
  vec2 p = uv + vec2(wobble + track * 0.02 * u_intensity, 0.0);
  float bleed = 0.003 * u_intensity;
  vec3 c = vec3(tex(p + vec2(bleed, 0.0)).r, tex(p).g, tex(p - vec2(bleed, 0.0)).b);
  c *= 0.92 + 0.08 * sin(uv.y * uSize.y * 1.6);
  c += (hash21(uv * uSize + floor(t * 30.0)) - 0.5) * 0.12 * u_intensity;
  c = mix(c, vec3(luma(c)), 0.2 * u_intensity);
  c += track * 0.15 * u_intensity;
  return vec4(clamp(c, 0.0, 1.0), tex(uv).a);
}
