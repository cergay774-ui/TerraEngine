vec4 effect(vec2 uv) {
  float e = sobel(uv, 1.0);
  float shade = luma(tex(uv).rgb);
  float hatch = step(fract((uv.x + uv.y) * uSize.y / 5.0), 0.5) * step(shade, 0.4);
  vec3 paper = vec3(0.97, 0.95, 0.9);
  vec3 s = paper * (1.0 - clamp(e * 2.0, 0.0, 1.0)) * (1.0 - hatch * 0.25);
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, s, u_intensity);
  return c;
}
