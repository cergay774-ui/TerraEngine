vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = toCentered(uv) * 7.0;
  vec4 acc = vec4(0.0);
  for (int layer = 0; layer < 2; layer++) {
    float fl = float(layer);
    vec2 q = p + vec2(0.0, uTime * (1.2 + fl * 0.6) * u_speed);
    vec2 cell = floor(q);
    vec2 h = hash22(cell + fl * 23.0);
    vec2 pos = cell + 0.25 + h * 0.5;
    vec2 d = rotate2(q - pos, uTime * 3.0 * (h.x - 0.5) * 4.0);
    d.x *= 0.4 + 0.6 * abs(sin(uTime * 4.0 + h.y * 10.0));
    float m = step(0.45, h.y) * fill(sdBox(d, vec2(0.12, 0.06)), 0.02);
    acc = mix(acc, vec4(hsv2rgb(vec3(h.x, 0.75, 1.0)), 1.0), m);
  }
  c.rgb = mix(c.rgb, acc.rgb, acc.a * u_intensity);
  return c;
}
