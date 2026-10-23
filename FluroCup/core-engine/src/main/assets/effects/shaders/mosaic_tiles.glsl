vec4 effect(vec2 uv) {
  vec2 p = uv * uSize / u_size;
  vec2 cell = floor(p);
  vec2 best = vec2(0.0);
  float bd = 10.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 n = cell + vec2(float(i), float(j));
      vec2 pt = n + hash22(n);
      float d = length(p - pt);
      if (d < bd) { bd = d; best = pt; }
    }
  }
  return tex(best * u_size * px());
}
