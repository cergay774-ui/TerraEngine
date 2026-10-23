vec4 effect(vec2 uv) {
  vec2 p = uv;
  if (u_mode < 0.5) p.x = p.x < 0.5 ? p.x : 1.0 - p.x;
  else if (u_mode < 1.5) p.x = p.x > 0.5 ? p.x : 1.0 - p.x;
  else if (u_mode < 2.5) p.y = p.y > 0.5 ? p.y : 1.0 - p.y;
  else p = 0.5 - abs(p - 0.5);
  return tex(p);
}
