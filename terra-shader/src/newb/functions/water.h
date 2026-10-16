#ifndef WATER_H
#define WATER_H

#include "utils.h"
#include "detection.h"
#include "sky.h"
#include "clouds.h"
#include "noise.h"
#include "time.h"

/*
  WATER

  Waves: up to 6 layers (TS_WATER_WAVES) of directional waves, from long
  swell to short ripples. Each layer is a sine wave in height; the normal
  uses the Gerstner formulation (NL_WATER_GERSTNER) which sharpens crests.
  On top of that:
  - amplitude of long and short layers is modulated by large scale world
    noise (32 blocks), so there are calm and rough areas, never the same
    pattern twice in view;
  - a world noise phase warp bends wave fronts, breaking the regular look.

  Every wave direction is an integer vector n (cycles per NL_WORLD_WRAP) and
  every speed is a whole number of cycles per NL_TIME_LOOP. So the pattern is
  exactly periodic in space and time and the coordinate/time wraps (see
  time.h) never show. The phase is computed with fract() on small numbers,
  which keeps precision even on mobile GPUs.

  Shading (per pixel path):
  - color by "depth" and view angle: thickness of water along the view ray,
    estimated from view angle + distance (RenderDragon gives no depth buffer
    to translucent geometry), shallow/clear when looking down, saturated
    deep blue at grazing angles and far away;
  - Fresnel (Schlick with roughness) decides reflection vs. transmission;
  - reflection of the procedural sky with sun/moon glow, optional clouds and
    aurora, a sun/moon specular spot whose lobe width follows roughness;
  - roughness blurs: specular lobe gets wider, clouds lose contrast and are
    skipped completely above 0.55 (higher roughness = cheaper).
*/

#define NL_WATER_GRAVITY 2.2 // dispersion constant (blocks/s^2), lower = slower long waves

// fresnel - Schlick's approximation
float calculateFresnel(float cosR, float r0) {
  float a = 1.0-cosR;
  float a2 = a*a;
  return r0 + (1.0-r0)*a2*a2*a;
}

// fresnel with roughness: rough surfaces reflect less at grazing angles
float calculateFresnelRough(float cosR, float r0, float roughness) {
  float a = 1.0-cosR;
  float a2 = a*a;
  return r0 + (max(1.0-roughness, r0)-r0)*a2*a2*a;
}

// One wave layer.
// acc.x: height, acc.yz: height gradient (d/dx, d/dz), acc.w: Gerstner normal y term
// n: direction, cycles per NL_WORLD_WRAP (integer), slope: k*A, warp: phase warp (cycles)
void nlWaveLayer(
  inout vec4 acc, inout float ampSum, highp vec2 p, highp float t, float camDist,
  vec2 n, float slope, float phase, float warp, float ampMod
) {
  float nLen = length(n);
  vec2 dir = n/nLen;
  float k = NL_TAU*nLen/NL_WORLD_WRAP;
  float wavelength = NL_WORLD_WRAP/nLen;
  // deep water dispersion, snapped to whole cycles per loop
  float cycles = floor(NL_WATER_WAVE_SPEED*sqrt(NL_WATER_GRAVITY*k)*(NL_TIME_LOOP/NL_TAU) + 0.5);

  highp float theta = NL_TAU*fract(dot(n, p)/NL_WORLD_WRAP - cycles*t/NL_TIME_LOOP + phase + warp);
  float s = sin(theta);
  float c = cos(theta);

  // fade short waves with distance (they would only shimmer)
  float fade = clamp(1.0 - camDist/(wavelength*NL_WATER_WAVE_FADE), 0.0, 1.0);
  float ka = NL_WATER_NORMAL_STRENGTH*slope*ampMod*fade;

  acc.x += (ka/k)*s;
  acc.yz += dir*(ka*c);
  acc.w += ka*s;
  ampSum += NL_WATER_NORMAL_STRENGTH*slope/k;
}

// p: wrapped world xz, t: wrapped time
// returns acc (see nlWaveLayer), hNorm: height normalized to [-1,1]
vec4 nlWaterWaves(highp vec2 p, highp float t, float camDist, out float hNorm) {
  vec4 acc = vec4(0.0, 0.0, 0.0, 0.0);
  float ampSum = 0.0001;

  #if TS_WATER_WAVES > 0
    // large scale variation: x = long wave amplitude, y = short wave amplitude, z = phase warp
    vec3 m = nlWorldNoise3(p, 32.0);
    float ampLong = mix(1.0, 0.25 + 1.5*m.x, NL_WATER_WAVE_VARIATION);
    float ampShort = mix(1.0, 0.3 + 1.4*m.y, NL_WATER_WAVE_VARIATION);
    float warp = 1.6*(m.z - 0.5);

    //                         direction n          slope  phase  warp         amplitude
    nlWaveLayer(acc, ampSum, p, t, camDist, vec2(40.0, 15.0),   0.20, 0.00,  0.6*warp, ampLong);  // 12.0 blocks
    #if TS_WATER_WAVES > 1
    nlWaveLayer(acc, ampSum, p, t, camDist, vec2(61.0, -28.0),  0.16, 0.37, -0.5*warp, ampLong);  // 7.6
    #endif
    #if TS_WATER_WAVES > 2
    nlWaveLayer(acc, ampSum, p, t, camDist, vec2(49.0, 92.0),   0.13, 0.71,  0.8*warp, ampShort); // 4.9
    #endif
    #if TS_WATER_WAVES > 3
    nlWaveLayer(acc, ampSum, p, t, camDist, vec2(158.0, -22.0), 0.10, 0.13, -0.7*warp, ampShort); // 3.2
    #endif
    #if TS_WATER_WAVES > 4
    nlWaveLayer(acc, ampSum, p, t, camDist, vec2(-103.0, 221.0),0.08, 0.53,  0.9*warp, ampShort); // 2.1
    #endif
    #if TS_WATER_WAVES > 5
    nlWaveLayer(acc, ampSum, p, t, camDist, vec2(203.0, -289.0),0.06, 0.89, -1.0*warp, ampShort); // 1.45
    #endif
  #endif

  hNorm = acc.x/ampSum;
  return acc;
}

// world space wave normal (up facing)
vec3 nlWaterNormal(vec4 acc) {
  return normalize(vec3(-acc.y, 1.0 - NL_WATER_GERSTNER*acc.w, -acc.z));
}

// vertical vertex offset for the water top surface, always <= 0 so water never
// rises into blocks above it. Call only for top surface vertices.
float nlWaterVertexOffset(highp vec2 p, highp float t, float camDist) {
  #if TS_WATER_VERTEX_WAVE
    if (camDist < 40.0) {
      float hNorm;
      nlWaterWaves(p, t, camDist, hNorm);
      float fade = smoothstep(40.0, 24.0, camDist);
      return 0.5*NL_WATER_WAVE_HEIGHT*(hNorm - 1.0)*fade;
    }
  #endif
  return 0.0;
}

// sun/moon specular spot. N, V (to camera) in world space
vec3 nlWaterSpecular(nl_environment env, vec3 N, vec3 V, float roughness, float shadow) {
  #if TS_WATER_SUN_SPEC
    if (env.end || env.underwater) {
      return vec3(0.0, 0.0, 0.0);
    }
    bool day = env.dayFactor > 0.0;
    vec3 L = nlWorldDir(day ? env.sunDir : env.moonDir);
    vec3 H = normalize(L + V);
    float r2 = roughness*roughness;
    float e = clamp(2.0/(r2*r2 + 0.0001) - 2.0, 4.0, 2048.0);
    float spec = pow(max(dot(N, H), 0.0), e)*(e + 8.0)*0.0398; // (e+8)/(8*pi)
    float vis = smoothstep(0.0, 0.12, L.y)*(1.0 - env.rainFactor)*shadow;
    vec3 col = day ? NL_SUNLIGHT_INTENSITY*mix(NL_NOON_SUNLIGHT_COL, mix(NL_DAWN_SUNLIGHT_COL, NL_DUSK_SUNLIGHT_COL, env.duskFactor), 1.0-L.y) : vec3(0.15, 0.2, 0.35);
    return (0.05*NL_WATER_SUN_SPEC*spec*vis)*col;
  #else
    return vec3(0.0, 0.0, 0.0);
  #endif
}

// sky + clouds reflection in direction R (world space, pointing away from surface)
vec3 nlSkyReflection(
  nl_skycolor skycol, nl_environment env, vec3 R, highp vec3 wPos, vec3 CAMERA_POS,
  highp float tRaw, float roughness, const bool clouds
) {
  R.y = max(R.y, 0.01); // never look below the horizon (void)
  R = normalize(R);
  // sky functions use a mirrored frame: pass -R (see nlWorldDir)
  vec3 refl = nlRenderSky(skycol, env, -R, tRaw, false);

  #ifdef NL_CLOUD_AURORA_REFLECTION
    // blurred clouds lose contrast; too blurry -> skip (cheaper)
    if (clouds && roughness < 0.55 && R.y > 0.0) {
      vec4 cloudRefl = nlCloudAuroraReflection(skycol, env, -R, wPos, CAMERA_POS, tRaw);
      refl = mix(refl, cloudRefl.rgb, cloudRefl.a*(1.0 - 1.6*roughness));
    }
  #endif

  return refl;
}

/*
  Per pixel water shading (TS_WATER_PER_PIXEL).
  tintLight: water texture * biome water color * light (linear)
  baseAlpha: vertex alpha (biome water_surface_transparency, more opaque far away)
  geomN: geometric normal facing the camera, V: direction to camera
  wPos: camera relative position, gPos: wrapped world position
  t: wrapped time, tRaw: raw time (for sky clouds)
  returns rgb and alpha for standard alpha blending
*/
vec4 nlWaterShade(
  vec3 tintLight, float baseAlpha, nl_skycolor skycol, nl_environment env, vec3 geomN, vec3 V,
  highp vec3 wPos, highp vec3 gPos, vec3 CAMERA_POS, vec3 torchColor, vec2 lit, float camDist,
  highp float t, highp float tRaw
) {
  // distant water is effectively rougher (normal detail below pixel size)
  float roughness = mix(TS_WATER_ROUGHNESS, max(TS_WATER_ROUGHNESS, 0.5), smoothstep(24.0, 96.0, camDist));
  float shadow = smoothstep(0.7, 0.86, lit.y); // lit = uv1^2, full sky = 0.879

  vec3 N;
  if (abs(geomN.y) > 0.5) {
    float hNorm;
    N = nlWaterNormal(nlWaterWaves(gPos.xz, t, camDist, hNorm));
    N.y *= sign(geomN.y);
  } else {
    // side faces (flowing water, waterfalls): ripples running down
    highp float f = NL_TAU*fract(0.5*gPos.y + 0.25*(gPos.x + gPos.z) + t*floor(1.5*NL_TIME_LOOP + 0.5)/NL_TIME_LOOP);
    N = normalize(geomN + vec3(0.0, 0.12*sin(f), 0.0) + 0.06*sin(f + 1.7)*vec3(geomN.z, 0.0, -geomN.x));
  }

  float cosV = clamp(dot(N, V), 0.0, 1.0);

  if (geomN.y < -0.5) {
    // camera underwater, looking up at the surface: Snell's window
    float window = smoothstep(0.6, 0.75, cosV);
    vec3 col = 0.6*skycol.horizon*(0.2 + 0.8*lit.y);
    return vec4(col, mix(0.94, 0.3, window));
  }

  // thickness of water along the view ray (depth guess / view angle + distance)
  float cosFlat = max(abs(V.y), 0.05);
  float path = NL_WATER_DEPTH_GUESS/cosFlat + 0.015*camDist;
  float thick = 1.0 - exp(-NL_WATER_ABSORPTION*path);

  vec3 waterCol = 0.45*tintLight*mix(NL_WATER_SHALLOW_COL, NL_WATER_DEEP_COL, thick);
  float murk = clamp((baseAlpha - 0.65)/0.3, 0.0, 1.0); // swamp / far water
  float alphaW = mix(mix(NL_WATER_MIN_OPACITY, 0.96, thick), 0.97, murk);

  // reflection
  vec3 R = reflect(-V, N);
  vec3 refl = nlSkyReflection(skycol, env, R, wPos, CAMERA_POS, tRaw, roughness, TS_WATER_CLOUD_REFL != 0);
  refl += torchColor*(0.6*NL_TORCHLIGHT_INTENSITY*lit.x*lit.x);
  if (!env.end) {
    refl *= 0.05 + lit.y*1.14; // no bright sky reflection under roofs / in caves
  }
  vec3 spec = nlWaterSpecular(env, N, V, roughness, shadow);

  float F = calculateFresnelRough(cosV, 0.02, roughness);

  // final = F*refl + (1-F)*(alphaW*waterCol + (1-alphaW)*background) + spec
  // expressed for blending: rgb*A + background*(1-A)
  float A = 1.0 - (1.0 - F)*(1.0 - alphaW);
  vec3 rgb = (F*refl + (1.0 - F)*alphaW*waterCol + spec)/max(A, 0.001);
  return vec4(rgb, A);
}

/*
  Per vertex water (TS_WATER_PER_PIXEL == 0): cheap path for weak devices.
  Same wave function, evaluated once per vertex (only long waves resolve on
  the 1-block vertex grid). Result is added in fragment as refl.rgb*refl.a.
*/
vec4 nlWater(
  inout vec4 color, inout vec3 wPos, nl_skycolor skycol, nl_environment env, vec4 COLOR, vec3 viewDir,
  vec3 cPos, highp vec3 gPos, vec3 CAMERA_POS, vec3 light, vec3 torchColor, vec2 lit,
  float fractCposY, float camDist, highp float t, highp float tRaw
) {
  float hNorm;
  vec4 w = nlWaterWaves(gPos.xz, t, camDist, hNorm);

  vec3 nrm; // points away from the camera side (newb convention)
  if (fractCposY > 0.0) { // top plane
    nrm = -nlWaterNormal(w);
  } else { // reflection for side plane
    float bump = 0.5 + 0.5*sin(NL_SNAP_W(3.0*NL_WATER_WAVE_SPEED)*t + cPos.y*PI_HALF);
    nrm.xz = normalize(viewDir.xz) + bump*(1.0-viewDir.xz*viewDir.xz)*NL_WATER_BUMP;
    nrm.y = (bump - 0.5)*NL_WATER_BUMP;
    nrm = normalize(nrm);
  }

  float cosR = dot(nrm, viewDir);
  viewDir = viewDir - 2.0*cosR*nrm ; // reflect(viewDir, nrm)

  vec3 waterRefl = nlRenderSky(skycol, env, viewDir, tRaw, false);

  #if defined(NL_CLOUD_AURORA_REFLECTION) && TS_WATER_CLOUD_REFL
    if (viewDir.y < 0.0 && TS_WATER_ROUGHNESS < 0.55) {
      vec4 cloudRefl = nlCloudAuroraReflection(skycol, env, viewDir, wPos, CAMERA_POS, tRaw);
      waterRefl = mix(waterRefl, cloudRefl.rgb, cloudRefl.a*(1.0 - 1.6*TS_WATER_ROUGHNESS));
    }
  #endif

  // torch light reflection
  float tc = 0.5+0.5*sin(16.0*viewDir.x)*sin(16.0*viewDir.z);
  waterRefl += torchColor*NL_TORCHLIGHT_INTENSITY*lit.x*tc*tc;

  // mask sky reflection under shade
  if (!env.end) {
    waterRefl *= 0.05 + lit.y*1.14;
  }

  #ifdef NL_WATER_REFL_MASK
    float mask = 0.05+0.05*sin(viewDir.x*12.0)*sin(viewDir.z*6.0);
    waterRefl *= smoothstep(mask-0.2,mask+0.13,viewDir.y*viewDir.y);
  #endif

  cosR = abs(cosR);
  float fresnel = calculateFresnelRough(cosR, 0.07, TS_WATER_ROUGHNESS);
  float opacity = 1.0-cosR;

  color.rgb *= 0.22*NL_WATER_TINT*(1.0-0.8*fresnel);
  color.a = mix(COLOR.a*NL_WATER_TRANSPARENCY, 1.0, opacity*opacity);

  return vec4(waterRefl, fresnel);
}

#endif
