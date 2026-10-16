#ifndef GRADE_H
#define GRADE_H

#include "utils.h"
#include "detection.h"

/*
  DIMENSION COLOR GRADING (TS_GRADE)

  Applied after tonemapping (display space) in RenderChunk, Actor* and
  ItemInHand* fragments, and in EndSky.

  Nether: the biome is recognised from FogColor. The fog color is reduced to
  chromaticity (rgb / (r+g+b)) so overall brightness does not matter, then
  compared to the vanilla fog color of each nether biome (NL_REF_* in
  config.h). When walking between biomes the game fades the fog color
  linearly from one biome to the other, so the fog lies on the segment
  between two references: the shader finds the best fitting pair and the
  position on it. So:
  - standing in a biome gives exactly its grade,
  - transitions blend smoothly and monotonically, no hard switch and no
    flash of a third biome in between.

  End: fixed purple-dark palette (End is detected by the custom fog color
  shipped in assets/fogs, same as upstream Newb).

  All branches depend only on uniforms, so they cost almost nothing in the
  overworld.
*/

vec3 nlChroma(vec3 c) {
  return c/max(c.r + c.g + c.b, 0.0001);
}

vec3 nlApplyGrade(vec3 col, vec3 tint, vec4 haze, float sat, float intensity) {
  vec3 g = col*tint;
  g = mix(vec3_splat(luminance(g)), g, sat);
  g = mix(g, haze.rgb, haze.a);
  return mix(col, max(g, vec3_splat(0.0)), intensity);
}

vec3 nlEndGrade(vec3 col) {
  #if TS_GRADE_ON
    vec3 g = nlApplyGrade(col*NL_GRADE_END_EXPOSURE, NL_GRADE_END_TINT, NL_GRADE_END_HAZE, NL_GRADE_END_SAT, 1.0);
    return mix(col, g, TS_GRADE);
  #else
    return col;
  #endif
}

// Projects chromaticity c onto the segment between references A and B.
// Keeps the pair that fits best; its weights are (1-t) for A and t for B.
// 5 weights are stored as vec4 w (refs 0..3) + float w4 (ref 4).
#define NL_GRADE_PAIR(A, B, WA, WA4, WB, WB4) { \
  vec3 a_ = nlChroma(A); \
  vec3 d_ = nlChroma(B) - a_; \
  float t_ = clamp(dot(c - a_, d_)/dot(d_, d_), 0.0, 1.0); \
  vec3 e_ = c - a_ - t_*d_; \
  float r_ = dot(e_, e_); \
  if (r_ < best) { best = r_; w = (1.0 - t_)*(WA) + t_*(WB); w4 = (1.0 - t_)*(WA4) + t_*(WB4); } \
}

vec3 nlNetherGrade(vec3 col, vec3 fogCol) {
  vec3 c = nlChroma(fogCol);

  // The game fades fog linearly between two biomes, so the current fog lies on
  // the segment between their reference colors: find that segment and the
  // position on it. Exact in a biome, smooth and monotonic in transitions.
  vec4 e0 = vec4(1.0, 0.0, 0.0, 0.0);
  vec4 e1 = vec4(0.0, 1.0, 0.0, 0.0);
  vec4 e2 = vec4(0.0, 0.0, 1.0, 0.0);
  vec4 e3 = vec4(0.0, 0.0, 0.0, 1.0);
  vec4 e4 = vec4(0.0, 0.0, 0.0, 0.0);
  float best = 1000.0;
  vec4 w = e0;
  float w4 = 0.0;
  NL_GRADE_PAIR(NL_REF_NETHER_WASTES,  NL_REF_CRIMSON_FOREST,  e0, 0.0, e1, 0.0)
  NL_GRADE_PAIR(NL_REF_NETHER_WASTES,  NL_REF_WARPED_FOREST,   e0, 0.0, e2, 0.0)
  NL_GRADE_PAIR(NL_REF_NETHER_WASTES,  NL_REF_SOULSAND_VALLEY, e0, 0.0, e3, 0.0)
  NL_GRADE_PAIR(NL_REF_NETHER_WASTES,  NL_REF_BASALT_DELTAS,   e0, 0.0, e4, 1.0)
  NL_GRADE_PAIR(NL_REF_CRIMSON_FOREST, NL_REF_WARPED_FOREST,   e1, 0.0, e2, 0.0)
  NL_GRADE_PAIR(NL_REF_CRIMSON_FOREST, NL_REF_SOULSAND_VALLEY, e1, 0.0, e3, 0.0)
  NL_GRADE_PAIR(NL_REF_CRIMSON_FOREST, NL_REF_BASALT_DELTAS,   e1, 0.0, e4, 1.0)
  NL_GRADE_PAIR(NL_REF_WARPED_FOREST,  NL_REF_SOULSAND_VALLEY, e2, 0.0, e3, 0.0)
  NL_GRADE_PAIR(NL_REF_WARPED_FOREST,  NL_REF_BASALT_DELTAS,   e2, 0.0, e4, 1.0)
  NL_GRADE_PAIR(NL_REF_SOULSAND_VALLEY,NL_REF_BASALT_DELTAS,   e3, 0.0, e4, 1.0)

  vec3 tint = w.x*NL_GRADE_WASTES_TINT + w.y*NL_GRADE_CRIMSON_TINT + w.z*NL_GRADE_WARPED_TINT + w.w*NL_GRADE_SOUL_TINT + w4*NL_GRADE_BASALT_TINT;
  vec4 haze = w.x*NL_GRADE_WASTES_HAZE + w.y*NL_GRADE_CRIMSON_HAZE + w.z*NL_GRADE_WARPED_HAZE + w.w*NL_GRADE_SOUL_HAZE + w4*NL_GRADE_BASALT_HAZE;
  float sat = w.x*NL_GRADE_WASTES_SAT + w.y*NL_GRADE_CRIMSON_SAT + w.z*NL_GRADE_WARPED_SAT + w.w*NL_GRADE_SOUL_SAT + w4*NL_GRADE_BASALT_SAT;

  return nlApplyGrade(col, tint, haze, sat, TS_GRADE);
}

// col: tonemapped color, fogCol: FogColor.rgb, fogCtrl: FogAndDistanceControl.xy / FogControl.xy
// fogAmount: fog blend of this pixel. Nether fog blends into the (ungraded) void
// clear color, so the grade fades out with fog to keep distant terrain matching it.
vec3 nlDimensionGrade(vec3 col, vec3 fogCol, vec2 fogCtrl, float fogAmount) {
  #if TS_GRADE_ON
    if (detectEnd(fogCol)) {
      return nlEndGrade(col);
    }
    if (detectNether(fogCol, fogCtrl)) {
      return mix(nlNetherGrade(col, fogCol), col, clamp(fogAmount, 0.0, 1.0));
    }
  #endif
  return col;
}

#endif
