vec4 effect(vec2 uv) {
  float t = floor(uTime * 6.0 * max(u_speed, 0.05));
  vec2 block = floor(uv * uSize / 32.0);
  float r = hash21(block + t);
  vec2 cell = (block + 0.5) * 32.0 / uSize;
  vec4 c = tex(uv);
  if (r < 0.25 * u_intensity) c = tex(cell);
  else if (r < 0.35 * u_intensity) c = tex(uv + (hash22(block + t) - 0.5) * 0.05);
  c.rgb = mix(c.rgb, floor(c.rgb * 6.0) / 6.0, 0.5 * u_intensity);
  return c;
}
