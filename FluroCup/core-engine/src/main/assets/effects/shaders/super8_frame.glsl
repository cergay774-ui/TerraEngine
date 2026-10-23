vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = abs(uv - 0.5) * 2.0;
  float border = max(smoothstep(0.92, 0.94, p.x), smoothstep(0.9, 0.92, p.y));
  float hole = 0.0;
  if (uv.x < 0.05) {
    float y = fract(uv.y * 6.0 + uTime * 0.5) - 0.5;
    hole = fill(sdBox(vec2((uv.x - 0.025) * aspect() * 6.0, y), vec2(0.18, 0.2)) - 0.05, 0.02);
  }
  c.rgb = mix(c.rgb, vec3(0.06, 0.05, 0.04), max(border, smoothstep(0.05, 0.045, uv.x)) * u_intensity);
  c.rgb = mix(c.rgb, vec3(0.9, 0.88, 0.8), hole * u_intensity);
  return c;
}
