vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec2 p = (uv - 0.5) * uSize;
  vec2 h = uSize * 0.5 - 36.0;
  vec2 a = abs(p);
  float corner = step(h.x - 50.0, a.x) * step(h.y - 50.0, a.y) * step(a.x, h.x) * step(a.y, h.y);
  float edge = max(step(h.x - 3.0, a.x) * step(a.x, h.x), step(h.y - 3.0, a.y) * step(a.y, h.y));
  c.rgb = mix(c.rgb, vec3(1.0), corner * edge * u_intensity);
  vec2 dotPos = vec2(-h.x + 40.0, h.y - 40.0);
  float blink = step(0.5, fract(uTime));
  float d = fill(length(p - dotPos) - 12.0, 1.5) * blink;
  c.rgb = mix(c.rgb, vec3(1.0, 0.15, 0.15), d * u_intensity);
  float secs = floor(uTime);
  vec2 q = (p - vec2(h.x - 150.0, h.y - 40.0)) / 14.0;
  float t = 0.0;
  t = max(t, digit(q, floor(secs / 600.0)));
  t = max(t, digit(q - vec2(1.3, 0.0), mod(floor(secs / 60.0), 10.0)));
  t = max(t, fill(length(q - vec2(2.2, 0.5)) - 0.12, 0.05));
  t = max(t, fill(length(q - vec2(2.2, -0.5)) - 0.12, 0.05));
  t = max(t, digit(q - vec2(3.1, 0.0), floor(mod(secs, 60.0) / 10.0)));
  t = max(t, digit(q - vec2(4.4, 0.0), mod(secs, 10.0)));
  c.rgb = mix(c.rgb, vec3(1.0), t * u_intensity);
  return c;
}
