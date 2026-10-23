vec4 effect(vec2 uv) {
  vec2 p = toCentered(uv);
  p.x += p.y * 0.15;
  float acc = 0.0;
  for (int layer = 0; layer < 2; layer++) {
    float fl = float(layer);
    vec2 q = p * vec2(40.0 + fl * 20.0, 3.0) + vec2(0.0, uTime * (6.0 + fl * 2.0) * u_speed);
    vec2 cell = floor(q);
    float h = hash21(cell + fl * 13.0);
    float y = fract(q.y + h);
    float x = abs(fract(q.x) - 0.5);
    acc += step(0.7, h) * smoothstep(0.08, 0.0, x) * smoothstep(0.0, 0.4, y) * step(y, 0.6);
  }
  vec4 c = tex(uv + vec2(0.0, acc * 0.003));
  c.rgb = mix(c.rgb * (1.0 - 0.15 * u_intensity), vec3(0.85, 0.9, 1.0), clamp(acc, 0.0, 1.0) * 0.5 * u_intensity);
  return c;
}
