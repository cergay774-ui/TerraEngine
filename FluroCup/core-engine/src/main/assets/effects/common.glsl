// Helpers shared by every FluroCup effect. Coordinates: uv in 0..1 with the origin at the
// bottom-left; "centered" space has the origin in the middle, y up and x scaled by the aspect,
// so circles stay round.

#define PI 3.14159265
#define TAU 6.2831853

float hash11(float p) {
  p = fract(p * 0.1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

float hash21(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * noise(p);
    p = p * 2.03 + 17.0;
    a *= 0.5;
  }
  return v;
}

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 rgb2hsv(vec3 c) {
  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 screen(vec3 a, vec3 b) { return 1.0 - (1.0 - a) * (1.0 - b); }

vec4 tex(vec2 uv) { return texture2D(uTexSampler, clamp(uv, vec2(0.0), vec2(1.0))); }

float aspect() { return uSize.x / uSize.y; }

vec2 toCentered(vec2 uv) { return (uv - 0.5) * vec2(uSize.x / uSize.y, 1.0); }

vec2 fromCentered(vec2 p) { return p / vec2(uSize.x / uSize.y, 1.0) + 0.5; }

vec2 rotate2(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Scales and rotates the picture about the centre, keeping its proportions.
vec2 transformUv(vec2 uv, float scale, float angle, vec2 offset) {
  vec2 p = toCentered(uv - offset);
  p = rotate2(p, -angle) / scale;
  return fromCentered(p);
}

vec2 px() { return 1.0 / uSize; }

// A small blur: 13 taps in a disc of `radius` pixels.
vec4 discBlur(vec2 uv, float radius) {
  vec4 acc = tex(uv) * 0.2;
  float w = 0.2;
  for (int i = 0; i < 12; i++) {
    float a = float(i) * 2.3999632;
    float r = sqrt((float(i) + 0.5) / 12.0) * radius;
    vec2 o = vec2(cos(a), sin(a)) * r * px();
    acc += tex(uv + o);
    w += 1.0;
  }
  return acc / w;
}

vec4 directionalBlur(vec2 uv, vec2 delta) {
  vec4 acc = vec4(0.0);
  for (int i = 0; i < 16; i++) {
    float t = float(i) / 15.0 - 0.5;
    acc += tex(uv + delta * t);
  }
  return acc / 16.0;
}

float sobel(vec2 uv, float spread) {
  vec2 o = px() * spread;
  float tl = luma(tex(uv + vec2(-o.x, o.y)).rgb);
  float t = luma(tex(uv + vec2(0.0, o.y)).rgb);
  float tr = luma(tex(uv + o).rgb);
  float l = luma(tex(uv - vec2(o.x, 0.0)).rgb);
  float r = luma(tex(uv + vec2(o.x, 0.0)).rgb);
  float bl = luma(tex(uv - o).rgb);
  float b = luma(tex(uv - vec2(0.0, o.y)).rgb);
  float br = luma(tex(uv + vec2(o.x, -o.y)).rgb);
  float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
  float gy = -bl - 2.0 * b - br + tl + 2.0 * t + tr;
  return sqrt(gx * gx + gy * gy);
}

float sdBox(vec2 p, vec2 b) {
  vec2 d = abs(p) - b;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdSegment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

float sdHeartShape(vec2 p) {
  p.x = abs(p.x);
  if (p.y + p.x > 1.0) return sqrt(dot(p - vec2(0.25, 0.75), p - vec2(0.25, 0.75))) - 0.35355339;
  vec2 a = p - vec2(0.0, 1.0);
  vec2 b = p - 0.5 * max(p.x + p.y, 0.0);
  return sqrt(min(dot(a, a), dot(b, b))) * sign(p.x - p.y);
}

float sdStarShape(vec2 p, float r, float rf) {
  vec2 k1 = vec2(0.809016994375, -0.587785252292);
  vec2 k2 = vec2(-k1.x, k1.y);
  p.x = abs(p.x);
  p -= 2.0 * max(dot(k1, p), 0.0) * k1;
  p -= 2.0 * max(dot(k2, p), 0.0) * k2;
  p.x = abs(p.x);
  p.y -= r;
  vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
  float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
  return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// 1 inside a shape with a soft edge `aa` wide, 0 outside.
float fill(float d, float aa) { return 1.0 - smoothstep(-aa, aa, d); }

// Seven-segment digit (0..9) in a 1x2 box centred on p; returns coverage.
float segment(vec2 p, vec2 a, vec2 b, float w) { return fill(sdSegment(p, a, b) - w, 0.02); }

float digit(vec2 p, float n) {
  float w = 0.08;
  float d = 0.0;
  // Segments: a top, b top-right, c bottom-right, d bottom, e bottom-left, f top-left, g middle.
  float a = segment(p, vec2(-0.35, 0.9), vec2(0.35, 0.9), w);
  float b = segment(p, vec2(0.4, 0.85), vec2(0.4, 0.05), w);
  float c = segment(p, vec2(0.4, -0.05), vec2(0.4, -0.85), w);
  float dd = segment(p, vec2(-0.35, -0.9), vec2(0.35, -0.9), w);
  float e = segment(p, vec2(-0.4, -0.05), vec2(-0.4, -0.85), w);
  float f = segment(p, vec2(-0.4, 0.85), vec2(-0.4, 0.05), w);
  float g = segment(p, vec2(-0.35, 0.0), vec2(0.35, 0.0), w);
  if (n < 0.5) d = max(max(max(a, b), max(c, dd)), max(e, f));
  else if (n < 1.5) d = max(b, c);
  else if (n < 2.5) d = max(max(a, b), max(max(g, e), dd));
  else if (n < 3.5) d = max(max(a, b), max(max(g, c), dd));
  else if (n < 4.5) d = max(max(f, g), max(b, c));
  else if (n < 5.5) d = max(max(a, f), max(max(g, c), dd));
  else if (n < 6.5) d = max(max(max(a, f), max(g, c)), max(dd, e));
  else if (n < 7.5) d = max(a, max(b, c));
  else if (n < 8.5) d = max(max(max(a, b), max(c, dd)), max(max(e, f), g));
  else d = max(max(max(a, b), max(c, dd)), max(f, g));
  return d;
}
