vec4 effect(vec2 uv) {
  vec4 c = tex(uv);
  vec3 r = hsv2rgb(vec3(fract(uv.x * 0.6 + uv.y * 0.3 + uTime * 0.2 * u_speed), 0.7, 1.0));
  c.rgb = mix(c.rgb, c.rgb * r * 1.3, u_intensity);
  return c;
}
