vec4 effect(vec2 uv) {
  vec4 c = discBlur(uv, 3.0);
  vec3 h = rgb2hsv(c.rgb);
  h.z = floor(h.z * u_levels + 0.5) / u_levels;
  h.y = min(h.y * 1.3, 1.0);
  float e = smoothstep(0.2, 0.45, sobel(uv, 1.0));
  vec3 s = hsv2rgb(h) * (1.0 - e);
  vec4 o = tex(uv);
  o.rgb = mix(o.rgb, s, u_intensity);
  return o;
}
