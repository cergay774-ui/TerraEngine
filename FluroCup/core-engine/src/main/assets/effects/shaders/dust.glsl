vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  float t = floor(uTime * 12.0);
  vec2 cell = floor(uv * vec2(14.0, 8.0));
  vec2 h = hash22(cell + t);
  vec2 pos = (cell + h) / vec2(14.0, 8.0);
  float d = length(toCentered(uv) - toCentered(pos)) * uSize.y;
  float speck = step(0.85, hash21(cell * 3.1 + t)) * smoothstep(3.0, 0.5, d);
  c.rgb = mix(c.rgb, vec3(0.05), speck * u_intensity);
  return c;
}
