vec4 effect(vec2 uv) {
  float t = floor(uTime * 8.0 * max(u_speed, 0.05));
  float row = floor(uv.y * 8.0);
  float r = hash21(vec2(row, t));
  float tear = step(0.75 - 0.4 * u_intensity, r) * (hash21(vec2(t, row)) - 0.5) * 0.4 * u_intensity;
  vec4 c = tex(vec2(fract(uv.x + tear), uv.y));
  float drop = step(0.92, hash21(vec2(floor(uv.y * 60.0), t))) * u_intensity;
  c.rgb = mix(c.rgb, vec3(c.g, 0.0, c.r), drop);
  return c;
}
