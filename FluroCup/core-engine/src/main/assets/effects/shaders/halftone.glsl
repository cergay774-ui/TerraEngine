vec4 effect(vec2 uv) {
  vec2 p = rotate2(uv * uSize, 0.785398) / u_size;
  vec2 cell = floor(p) + 0.5;
  vec2 center = rotate2(cell * u_size, -0.785398) * px();
  float l = luma(tex(center).rgb);
  float r = sqrt(1.0 - l) * 0.7;
  float dotMask = fill(length(fract(p) - 0.5) - r, 0.08);
  vec4 c = tex(uv);
  c.rgb = mix(c.rgb, vec3(1.0 - dotMask), u_intensity);
  return c;
}
