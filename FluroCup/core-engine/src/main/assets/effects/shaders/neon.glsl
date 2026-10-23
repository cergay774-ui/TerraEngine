vec4 effect(vec2 uv) {
  float e = clamp(sobel(uv, 1.5) * 2.0, 0.0, 1.0);
  float g = clamp(sobel(uv, 4.0) * 1.2, 0.0, 1.0) * u_glow;
  vec3 col = hsv2rgb(vec3(fract(uv.y * 0.5 + uTime * 0.2 * u_speed), 0.8, 1.0));
  vec3 base = tex(uv).rgb * 0.15;
  return vec4(clamp(base + col * (e + g * 0.6), 0.0, 1.0), tex(uv).a);
}
