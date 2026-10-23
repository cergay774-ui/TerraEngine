vec4 effect(vec2 uv) {
  float e = smoothstep(0.1, 0.5, sobel(uv, 1.5));
  float glow = smoothstep(0.05, 0.4, sobel(uv, 4.0));
  vec3 c = tex(uv).rgb * (1.0 - 0.6 * u_intensity);
  c += u_color * (e + glow * 0.5) * 1.4 * u_intensity;
  return vec4(clamp(c, 0.0, 1.0), tex(uv).a);
}
