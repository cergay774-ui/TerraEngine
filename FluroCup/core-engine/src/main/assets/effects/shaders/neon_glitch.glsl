vec4 effect(vec2 uv) {
  float t = floor(uTime * 10.0);
  float jump = step(0.8, hash21(vec2(floor(uv.y * 12.0), t))) * (hash11(t) - 0.5) * 0.05 * u_intensity;
  vec2 p = uv + vec2(jump, 0.0);
  float e = sobel(p, 1.5);
  vec3 base = tex(p).rgb;
  vec3 c = vec3(tex(p + vec2(0.006 * u_intensity, 0.0)).r, base.g, tex(p - vec2(0.006 * u_intensity, 0.0)).b);
  c += u_color * smoothstep(0.1, 0.6, e) * 1.5 * u_intensity;
  return vec4(clamp(c, 0.0, 1.0), tex(uv).a);
}
