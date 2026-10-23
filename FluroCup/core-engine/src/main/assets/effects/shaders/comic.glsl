vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec3 q = floor(c.rgb * 4.0 + 0.5) / 4.0;
  q = clamp(mix(vec3(luma(q)), q, 1.5), 0.0, 1.0);
  float e = smoothstep(0.25, 0.5, sobel(uv, 1.5));
  vec2 dp = fract(uv * uSize / 6.0) - 0.5;
  float dots = fill(length(dp) - 0.25, 0.1) * step(luma(c.rgb), 0.5) * 0.25;
  vec3 s = q * (1.0 - dots) * (1.0 - e);
  c.rgb = mix(c.rgb, s, u_intensity);
  return c;
}
