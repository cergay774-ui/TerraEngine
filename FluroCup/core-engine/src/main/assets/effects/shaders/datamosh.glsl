vec4 effect(vec2 uv) {
  float t = uTime * u_speed;
  vec2 block = floor(uv * vec2(16.0, 9.0));
  vec2 flow = (vec2(noise(block * 0.7 + t), noise(block * 0.7 - t + 9.0)) - 0.5) * 0.15 * u_intensity;
  float smear = step(0.5, noise(block * 0.3 + floor(t * 2.0)));
  vec4 c = tex(uv + flow * smear);
  c.rgb = mix(c.rgb, tex(uv + flow * 2.0).rgb, 0.3 * smear * u_intensity);
  return c;
}
