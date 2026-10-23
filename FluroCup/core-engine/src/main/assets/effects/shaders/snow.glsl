vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = toCentered(uv);
  float acc = 0.0;
  for (int layer = 0; layer < 3; layer++) {
    float fl = float(layer);
    float scale = 6.0 + fl * 4.0;
    vec2 q = p * scale + vec2(sin(uTime * 0.6 + fl) * 0.5, uTime * (1.0 + fl * 0.3) * u_speed);
    vec2 cell = floor(q);
    vec2 h = hash22(cell + fl * 17.0);
    vec2 pos = cell + 0.15 + h * 0.7;
    acc += step(0.35, h.y) * fill(length(q - pos) - (0.06 - fl * 0.012), 0.03);
  }
  c.rgb = mix(c.rgb, vec3(1.0), clamp(acc, 0.0, 1.0) * u_intensity);
  return c;
}
