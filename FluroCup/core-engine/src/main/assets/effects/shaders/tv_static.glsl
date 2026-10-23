vec4 effect(vec2 uv) {
  float t = floor(uTime * 30.0 * max(u_speed, 0.05));
  float n = hash21(floor(uv * uSize / 2.0) + t * 13.0);
  float roll = smoothstep(0.0, 0.1, abs(fract(uv.y - uTime * 0.3 * u_speed) - 0.5));
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, vec3(n), u_intensity * (0.6 + 0.4 * (1.0 - roll)));
  return c;
}
