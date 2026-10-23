float twoDigits(vec2 p, float v) {
  float tens = floor(v / 10.0);
  float ones = mod(floor(v), 10.0);
  return max(digit(p + vec2(0.6, 0.0), tens), digit(p - vec2(0.6, 0.0), ones));
}
vec4 effect(vec2 uv) {
  float wobble = (noise(vec2(uv.y * 40.0, uTime * 3.0)) - 0.5) * 0.004 * u_intensity;
  vec2 p = uv + vec2(wobble, 0.0);
  vec3 c = vec3(tex(p + vec2(0.003 * u_intensity, 0.0)).r, tex(p).g, tex(p - vec2(0.003 * u_intensity, 0.0)).b);
  c *= 0.94 + 0.06 * sin(uv.y * uSize.y * 1.6);
  c += (hash21(uv * uSize + floor(uTime * 30.0)) - 0.5) * 0.08 * u_intensity;
  vec2 q = (uv - vec2(0.62, 0.08)) * vec2(aspect(), 1.0) * 28.0;
  float text = 0.0;
  text = max(text, twoDigits(q, u_day));
  text = max(text, twoDigits(q - vec2(3.2, 0.0), u_month));
  text = max(text, twoDigits(q - vec2(6.4, 0.0), u_year));
  text = max(text, fill(length(q - vec2(1.6, -0.9)) - 0.12, 0.05));
  text = max(text, fill(length(q - vec2(4.8, -0.9)) - 0.12, 0.05));
  c = mix(c, vec3(1.0, 0.75, 0.25), text);
  return vec4(clamp(c, 0.0, 1.0), tex(uv).a);
}
