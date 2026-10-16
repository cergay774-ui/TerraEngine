#ifndef NL_CONFIG_H
#define NL_CONFIG_H

/*
  TERRA SHADER CONFIG (based on Newb X Legacy config)

  There are two kinds of options in this file:

  1. TS_* - QUALITY PRESET PARAMETERS
     These come from `presets.toml` (one value per subpack). The build tool
     passes them to the compiler as defines, e.g. `water_waves = 4` in
     presets.toml becomes `TS_WATER_WAVES=4`. For every float parameter the
     tool also defines `<NAME>_ON` (1 if value != 0.0, else 0), because the
     preprocessor can't compare floats in #if.
     The defaults below are only used when compiling without the tool
     (they match the "medium" preset). Do not tune presets here - edit
     presets.toml instead.

  2. NL_* - ARTISTIC OPTIONS (colors, intensities)
     Shared by all presets. Same rules as the original Newb config:
     - [toggle] options can be commented out with '//' to disable
     - colors are vec3(red,green,blue), 1.0 = 100%
     - values must be decimal (32.0, not 32)

  Remember to rebuild the shader after making changes.
*/

/* ---------------------------------------------------------------------------
   1. QUALITY PRESET PARAMETERS (defaults = "medium")
--------------------------------------------------------------------------- */

#ifndef TS_WATER_WAVES
  #define TS_WATER_WAVES 4          // 0 = flat water, 1..6 = number of wave layers (sine + Gerstner)
#endif
#ifndef TS_WATER_PER_PIXEL
  #define TS_WATER_PER_PIXEL 1      // 1 = wave normals/reflections per pixel, 0 = per vertex (cheap)
#endif
#ifndef TS_WATER_VERTEX_WAVE
  #define TS_WATER_VERTEX_WAVE 1    // 1 = move water surface vertices with the waves
#endif
#ifndef TS_WATER_ROUGHNESS
  #define TS_WATER_ROUGHNESS 0.3    // 0.05 mirror ~ 1.0 blurry. Higher = blurrier AND cheaper
  #define TS_WATER_ROUGHNESS_ON 1
#endif
#ifndef TS_WATER_CLOUD_REFL
  #define TS_WATER_CLOUD_REFL 0     // reflect clouds/aurora on water (skipped when roughness is high)
#endif
#ifndef TS_WATER_SUN_SPEC
  #define TS_WATER_SUN_SPEC 1       // sun/moon specular spot on water
#endif
#ifndef TS_CAUSTICS
  #define TS_CAUSTICS 1             // 0 = off, 1 = per vertex, 2 = per pixel
#endif
#ifndef TS_UNDERWATER_DISTORT
  #define TS_UNDERWATER_DISTORT 0.08 // underwater wobble strength
  #define TS_UNDERWATER_DISTORT_ON 1
#endif
#ifndef TS_PUDDLES
  #define TS_PUDDLES 1              // rain puddles
#endif
#ifndef TS_PUDDLE_RIPPLES
  #define TS_PUDDLE_RIPPLES 0       // animated rain drop rings in puddles
#endif
#ifndef TS_PUDDLE_CLOUD_REFL
  #define TS_PUDDLE_CLOUD_REFL 0    // reflect clouds in puddles
#endif
#ifndef TS_PUDDLE_DIST
  #define TS_PUDDLE_DIST 40.0       // puddles are drawn up to this distance (blocks)
  #define TS_PUDDLE_DIST_ON 1
#endif
#ifndef TS_WET_GROUND
  #define TS_WET_GROUND 1           // darken exposed ground while raining
#endif
#ifndef TS_AO
  #define TS_AO 0.5                 // extra corner ambient occlusion, 0.0 = vanilla only
  #define TS_AO_ON 1
#endif
#ifndef TS_FACE_SHADING
  #define TS_FACE_SHADING 0.6       // shade block faces by sun/moon direction, 0.0 = off
  #define TS_FACE_SHADING_ON 1
#endif
#ifndef TS_EMISSIVE
  #define TS_EMISSIVE 0.8           // glow of bright blocks that emit light (sea lantern, shroomlight...)
  #define TS_EMISSIVE_ON 1
#endif
#ifndef TS_LAVA_FLOW
  #define TS_LAVA_FLOW 1            // lava UV flow distortion (per pixel)
#endif
#ifndef TS_GRADE
  #define TS_GRADE 1.0              // nether biome / end color grading intensity, 0.0 = off
  #define TS_GRADE_ON 1
#endif
#ifndef TS_PLANTS_WAVE
  #define TS_PLANTS_WAVE 1          // waving plants, leaves, lanterns
#endif
#ifndef TS_WAVE_RANGE
  #define TS_WAVE_RANGE 13.0        // plants wave up to this distance (blocks)
  #define TS_WAVE_RANGE_ON 1
#endif
#ifndef TS_GLOW_SHIMMER
  #define TS_GLOW_SHIMMER 1         // ore glow shimmer
#endif
#ifndef TS_RAIN_MIST
  #define TS_RAIN_MIST 1            // wind blown rain mist
#endif
#ifndef TS_CLOUDY_FOG
  #define TS_CLOUDY_FOG 1           // patchy fog at distance
#endif
#ifndef TS_SHOOTING_STAR
  #define TS_SHOOTING_STAR 1
#endif
#ifndef TS_AURORA
  #define TS_AURORA 1
#endif
#ifndef TS_CLOUD_TYPE
  #define TS_CLOUD_TYPE 1           // 0:vanilla, 1:soft, 2:rounded, 3:realistic
#endif

/* ---------------------------------------------------------------------------
   2. ARTISTIC OPTIONS
--------------------------------------------------------------------------- */

/* Animation timing (see functions/time.h)
   All RenderChunk animation uses the game render timer (seconds), never a
   frame counter. Time is wrapped every NL_TIME_LOOP seconds and every
   animation frequency is snapped to a whole number of cycles per loop, so
   the wrap is invisible and float precision never degrades in long sessions. */
#define NL_TIME_LOOP  1800.0  // seconds
#define NL_WORLD_WRAP 512.0   // blocks; world-space effects repeat after this distance (exactly, no seams)

/* Color correction */
#define NL_TONEMAP_TYPE 3              // 1:Exponential, 2:Reinhard, 3:Extended Reinhard, 4:ACES
#define NL_GAMMA 1.33                  // 0.3 low ~ 2.0 high
//#define NL_EXPOSURE 1.3              // [toggle] 0.5 dark ~ 3.0 bright
//#define NL_SATURATION 1.4            // [toggle] 0.0 grayscale ~ 4.0 super saturated
//#define NL_TINT                      // [toggle] enable light/dark tone tinting
#define NL_TINT_LOW  vec3(0.3,0.5,1.4) // color tint for dark tone
#define NL_TINT_HIGH vec3(1.4,0.7,0.3) // color tint for light tone

/* Lighting */
#define NL_SUNLIGHT_INTENSITY   3.3  // 1.0 weak ~ 5.0 bright
#define NL_TORCHLIGHT_INTENSITY 1.0  // 0.5 weak ~ 3.0 bright
#define NL_SHADOW_INTENSITY     0.7  // 0.0 no shadow ~ 1.0 strong shadow
#define NL_SHADOW_SOFTNESS      0.07 // 0.01 sharp ~ 0.15 soft (skylight-lightmap shadow edge)
#define NL_MIN_LIGHTING_BOOST   1.5  // 1.0 minimal lighting boost for dark areas ~ 3.0 brighter dark areas
//#define NL_BLINKING_TORCH  // [toggle] flickering light
#define NL_CLOUD_SHADOW      // [toggle] cloud shadow (simple clouds only)

/* Ambient light for nether/end */
#define NL_NETHER_AMBIENT vec3(3.0,2.16,1.89)
#define NL_END_AMBIENT    vec3(1.98,1.25,2.3)

/* Sun/moon light color - separate palettes for dawn, day, dusk and night.
   Transitions are smooth: dawn/dusk weight follows sun height, the
   dawn<->dusk choice switches at noon/midnight where its weight is 0. */
#define NL_DAWN_SUNLIGHT_COL   vec3(1.0,0.55,0.32) // sunrise: soft pink-gold
#define NL_NOON_SUNLIGHT_COL   vec3(1.0,0.75,0.57)
#define NL_DUSK_SUNLIGHT_COL   vec3(1.0,0.36,0.08) // sunset: deep orange
#define NL_NIGHT_MOONLIGHT_COL vec3(0.012,0.035,0.21) // cold blue moonlight

/* Torch colors (warm) */
#define NL_OVERWORLD_TORCH_COL  vec3(1.0,0.52,0.18)
#define NL_UNDERWATER_TORCH_COL vec3(1.0,0.52,0.18)
#define NL_NETHER_TORCH_COL     vec3(1.0,0.52,0.18)
#define NL_END_TORCH_COL        vec3(1.0,0.52,0.18)

/* Fog */
#define NL_FOG 1.0                // [toggle] 0.1 subtle ~ 1.0 blend with sky completely
#define NL_MIST_DENSITY 0.18      // 0.0 no mist ~ 1.0 misty
#define NL_RAIN_MIST_OPACITY 0.12 // [toggle] 0.04 very subtle ~ 0.5 thick rain mist blow
#define NL_CLOUDY_FOG 0.1         // [toggle] 0.0 subtle - 0.8 dense fog clouds

/* Sky */
#define NL_SKY_VOID_FACTOR     0.5
#define NL_SKY_VOID_DARKNESS   0.3
#define NL_SKY_RAIN_MIX_FACTOR 0.9

/* Sky colors - zenith=top, horizon=bottom */
#define NL_DAWN_ZENITH_COL   vec3(0.12,0.38,0.75)
#define NL_DAWN_HORIZON_COL  vec3(2.6,0.75,0.8)
#define NL_DAWN_EDGE_COL     vec3(2.0,1.0,1.0)
#define NL_DUSK_ZENITH_COL   vec3(0.1,0.3,0.62)
#define NL_DUSK_HORIZON_COL  vec3(3.0,0.4,0.15)
#define NL_DUSK_EDGE_COL     vec3(2.2,0.75,0.4)
#define NL_DAY_ZENITH_COL    vec3(0.3,0.9,2.0)
#define NL_DAY_HORIZON_COL   vec3(1.0,1.6,1.8)
#define NL_DAY_EDGE_COL      vec3(1.44,1.56,1.62)
#define NL_NIGHT_ZENITH_COL  vec3(0.008,0.048,0.08)
#define NL_NIGHT_HORIZON_COL vec3(0.02,0.06,0.1)
#define NL_NIGHT_EDGE_COL    vec3(0.04,0.08,0.1)
#define NL_RAIN_ZENITH_COL   vec3(0.47,0.51,0.56)
#define NL_RAIN_HORIZON_COL  vec3(0.6,0.6,0.6)

#define NL_END_ZENITH_COL    vec3(0.08,0.001,0.1)
#define NL_END_HORIZON_COL   vec3(0.6,0.02,0.6)

/* Rainbow */
#define NL_RAINBOW           // [toggle] enable rainbow in sky
#define NL_RAINBOW_CLEAR 0.0 // 0.3 subtle ~ 1.0 bright during clear weather
#define NL_RAINBOW_RAIN  0.4 // 0.3 subtle ~ 1.0 bright during rain weather

/* Ore glow intensity */
#define NL_GLOW_TEX 2.3           // 0.4 weak ~ 8.0 bright
#define NL_GLOW_SHIMMER 0.8       // [toggle] 0.1 subtle ~ 1.0 100% shimmer
#define NL_GLOW_SHIMMER_SPEED 0.9 // 0.5 slow - 2.0 fast
//#define NL_GLOW_LEAK 0.6        // [toggle] 0.08 subtle ~ 1.0 100% brightness of NL_GLOW_TEX

/* Emissive blocks detected by block light (TS_EMISSIVE) */
#define NL_EMISSIVE_MIN_LIGHT 0.86 // lightmap level where glow starts (0.875 = light 14)
#define NL_EMISSIVE_MIN_BRIGHT 0.55 // only bright texels glow

/* Waving */
#define NL_PLANTS_WAVE 0.05    // [toggle] 0.02 gentle ~ 0.4 violent
#define NL_LANTERN_WAVE 0.16   // [toggle] 0.05 subtle ~ 0.4 large swing
#define NL_WAVE_SPEED 2.8      // 0.5 slow wave ~ 5.0 very fast wave
//#define NL_EXTRA_PLANTS_WAVE // [toggle] !dont use! wave using texture coords (1.21.0 vanilla 2048x1024)
#define NL_WAVE_RANGE TS_WAVE_RANGE

/* Water (surface) */
#define NL_WATER_TRANSPARENCY 0.9 // 0.0 transparent ~ 1.0 normal (per vertex water)
#define NL_WATER_BUMP 0.09        // 0.001 plain ~ 0.2 bumpy water (per vertex water)
#define NL_WATER_WAVE_SPEED  0.8  // 0.2 calm ~ 2.0 turbulent
#define NL_WATER_TEX_OPACITY 0.3  // 0.0 plain water ~ 1.0 vanilla water texture
#define NL_WATER_TINT vec3(0.52,0.9,0.45)
//#define NL_WATER_REFL_MASK      // [toggle] fake water reflection mask

/* Water waves (TS_WATER_WAVES layers) */
#define NL_WATER_WAVE_HEIGHT 0.05     // vertical surface movement in blocks (TS_WATER_VERTEX_WAVE)
#define NL_WATER_NORMAL_STRENGTH 1.0  // 0.3 calm ~ 1.5 choppy
#define NL_WATER_GERSTNER 0.75        // 0.0 pure sine waves ~ 1.0 sharp Gerstner crests
#define NL_WATER_WAVE_VARIATION 0.65  // 0.0 uniform ~ 1.0 calm and rough areas across the world
#define NL_WATER_WAVE_FADE 14.0       // short waves fade out at (wavelength * this) blocks, anti-shimmer

/* Water color by depth and view angle */
#define NL_WATER_SHALLOW_COL vec3(0.30,0.85,0.80) // near / looking straight down
#define NL_WATER_DEEP_COL    vec3(0.03,0.16,0.42) // far / grazing angle
#define NL_WATER_DEPTH_GUESS 2.5      // assumed water depth in blocks (no depth buffer available)
#define NL_WATER_ABSORPTION  0.22     // 0.1 clear ~ 1.0 murky
#define NL_WATER_MIN_OPACITY 0.15     // opacity when looking straight down at shallow water
#define NL_WATER_SUN_SPEC 1.0         // sun spot brightness

/* Underwater */
#define NL_UNDERWATER_BRIGHTNESS 0.8         // 0.0 dark ~ 3.0 bright
#define NL_CAUSTIC_INTENSITY 1.9             // 0.5 weak ~ 5.0 bright
#define NL_UNDERWATER_WAVE TS_UNDERWATER_DISTORT
#define NL_UNDERWATER_STREAKS 1.0            // [toggle] 0.8 subtle - 2.0 bright streaks from top
#define NL_UNDERWATER_TINT vec3(0.9,1.0,0.9) // fog tint color when underwater

/* Cloud type */
#define NL_CLOUD_TYPE TS_CLOUD_TYPE

/* Vanilla cloud settings - make sure to remove clouds.png when using this */
#define NL_CLOUD0_THICKNESS 2.1      // 0.5 slim ~ 8.0 fat
#define NL_CLOUD0_RAIN_THICKNESS 4.0 // 0.5 slim ~ 8.0 fat
#define NL_CLOUD0_OPACITY 0.9        // 0.0 invisible ~ 1.0 opaque
#define NL_CLOUD0_MULTILAYER         // [toggle] extra cloud layer

/* Soft cloud settings */
#define NL_CLOUD1_SCALE vec2(0.016, 0.022) // 0.003 large ~ 0.2 tiny
#define NL_CLOUD1_DEPTH 1.3                // 0.0 no bump ~ 10.0 large bumps
#define NL_CLOUD1_SPEED 0.04               // 0.0 static ~ 0.4 fast moving
#define NL_CLOUD1_DENSITY 0.54             // 0.1 less clouds ~ 0.8 more clouds
#define NL_CLOUD1_OPACITY 0.9              // 0.0 invisible ~ 1.0 opaque

/* Rounded cloud settings */
#define NL_CLOUD2_THICKNESS 2.1            // 0.5 slim ~ 5.0 fat
#define NL_CLOUD2_RAIN_THICKNESS 2.5       // 0.5 slim ~ 5.0 fat
#define NL_CLOUD2_STEPS 5                  // 3 low quality ~ 16 high quality
#define NL_CLOUD2_SCALE vec2(0.033, 0.033) // 0.003 large ~ 0.3 tiny
#define NL_CLOUD2_SHAPE vec2(0.5, 0.4)     // 0.0 round ~ 1.0 box vec2(horizontal shape, vertical shape)
#define NL_CLOUD2_DENSITY 25.0             // 1.0 blurry ~ 100.0 sharp
#define NL_CLOUD2_VELOCITY 0.8             // 0.0 static ~ 4.0 very fast
//#define NL_CLOUD2_LAYER2                      // [toggle] extra cloud layer
#define NL_CLOUD2_LAYER2_OFFSET 143.0           // 30.0 near ~ 300.0 very high
#define NL_CLOUD2_LAYER2_THICKNESS 2.5          // 0.7 slim ~ 5.0 fat
#define NL_CLOUD2_LAYER2_RAIN_THICKNESS 3.0     // 0.7 slim ~ 5.0 fat
#define NL_CLOUD2_LAYER2_STEPS 3                // 3 low quality ~ 16 high quality
#define NL_CLOUD2_LAYER2_SCALE vec2(0.03, 0.03) // 0.003 large ~ 0.3 tiny
#define NL_CLOUD2_LAYER2_SHAPE vec2(0.5, 0.4)   // 0.0 round ~ 1.0 box vec2(horizontal shape, vertical shape)
#define NL_CLOUD2_LAYER2_DENSITY 25.0           // 1.0 blurry ~ 100.0 sharp
#define NL_CLOUD2_LAYER2_VELOCITY 0.8           // 0.0 static ~ 4.0 very fast

/* Realistic cloud settings */
#define NL_CLOUD3_SCALE vec2(0.03, 0.03) // 0.003 large ~ 1.0 tiny
#define NL_CLOUD3_SPEED 0.005            // 0.0 static ~ 4.0 fast moving
#define NL_CLOUD3_SHADOW 0.9             // 0.1 subtle ~ 1.0 dark
#define NL_CLOUD3_SHADOW_OFFSET 0.3      // 0.05 minimal ~ 1.0 large

/* Aurora settings */
#define NL_AURORA 1.2           // [toggle] 0.4 dim ~ 4.0 very bright
#define NL_AURORA_VELOCITY 0.03 // 0.0 static ~ 0.3 very fast
#define NL_AURORA_SCALE 0.04    // 0.002 large ~ 0.4 tiny
#define NL_AURORA_WIDTH 0.18    // 0.04 thin line ~ 0.4 thick lines
#define NL_AURORA_COL1 vec3(0.1,1.0,0.0)
#define NL_AURORA_COL2 vec3(0.1,0.0,1.0)

#define NL_CLOUD_AURORA_REFLECTION // [toggle] simple clouds/aurora reflection

/* Shooting star */
#define NL_SHOOTING_STAR 1.0        // [toggle] 0.2 dim ~ 1.0 bright
#define NL_SHOOTING_STAR_PERIOD 6.0 // 0.4 fast ~ 12.0 slow (12 secs)
#define NL_SHOOTING_STAR_DELAY 64.0 // 0.0 no delay ~ 100.0 long time (100 secs)

/* Galaxy */
//#define NL_GALAXY_STARS 2.0           // [toggle] 0.1 dim - 4.0 bright
#define NL_GALAXY_VIBRANCE 0.7          // 0.0 white - 1.0 colorful
#define NL_GALAXY_SPEED 0.03            // 0.01 slow motion - 0.2 fast motion
#define NL_GALAXY_DAY_VISIBILITY 0.0    // 0.0 invisible - 1.0 visible

/* Chunk loading slide in animation */
//#define NL_CHUNK_LOAD_ANIM 100.0 // [toggle] -600.0 fall from top ~ 600.0 rise from bottom

/* Sun/Moon */
#define NL_SUN_SIZE  1.0           // 0.3 tiny ~ 4.0 massive
#define NL_MOON_SIZE 1.0           // 0.3 tiny ~ 4.0 massive
#define NL_SUN_PATH_YAW    15.0 //
#define NL_MOON_PATH_YAW   17.0 //
#define NL_SUN_PATH_TILT   31.0 //
#define NL_MOON_PATH_TILT -28.0 //
#define NL_SUN_TILT        45.0 // 0.0 no tilt ~ 90.0 tilt of 90 degrees
#define NL_MOON_TILT       45.0 // 0.0 no tilt ~ 90.0 tilt of 90 degrees

/* Fake godrays during sunrise/sunset */
//#define NL_GODRAY 0.3 // [toggle] 0.1 subtle ~ 0.8 strong

/* Wet ground and puddles (TS_WET_GROUND, TS_PUDDLES) */
#define NL_GROUND_RAIN_WETNESS 1.0  // 0.0 no wetness ~ 1.0 fully wet blocks when raining
#define NL_GROUND_RAIN_PUDDLES 0.7  // 0.0 no puddles ~ 1.0 puddles (per vertex fallback only)
#define NL_PUDDLE_COVERAGE 0.42     // 0.1 few puddles ~ 0.8 flooded, share of open ground at full rain
#define NL_PUDDLE_SIZE 1.0          // 0.5 small ~ 2.0 large
#define NL_PUDDLE_WET_EDGE 0.12     // width of the darkened wet rim around puddles
#define NL_PUDDLE_DARKEN 0.45       // how dark wet ground gets
#define NL_PUDDLE_RIPPLE_SPEED 1.1  // drops per second per cell
#define NL_PUDDLE_RIPPLE_STRENGTH 0.6
#define NL_PUDDLE_MIN_SKYLIGHT 0.9  // lightmap sky level for "open sky" (0.9375 = 15)

/* Entity (Actor, ItemInHand) */
#define NL_ENTITY_BRIGHTNESS     0.65 // 0.1 dark ~ 1.6 bright
#define NL_ENTITY_EDGE_HIGHLIGHT 0.41 // [toggle] 0.0 no highlight ~ 1.6 bright highlight

/* Weather particles */
#define NL_WEATHER_SPECK 0.6         // [toggle] 0.0 vanilla texture ~ 1.0 soft speck
#define NL_WEATHER_RAIN_SLANT 4.0    // 1.0 minimal ~ 8.0 violent
#define NL_WEATHER_PARTICLE_SIZE 1.0 // 0.5 tiny ~ 4.0 large

/* Lava effects */
#define NL_LAVA_NOISE            // [toggle] darken lava in certain regions
//#define NL_LAVA_NOISE_BUMP 0.2 // [toggle] 0.1 subtle ~ 0.8 massive waves
#define NL_LAVA_NOISE_SPEED 0.2  // 0.0 still ~ 0.8 fast
#define NL_LAVA_FLOW_SPEED 0.03  // tiles per second (TS_LAVA_FLOW)
#define NL_LAVA_FLOW_WARP 0.08   // UV distortion strength
#define NL_LAVA_PULSE 0.25       // 0.0 steady ~ 0.6 strong glow pulsing
#define NL_LAVA_GLOW 1.6         // glow of hot lava texels

/* Nether biome color grading (TS_GRADE)
   The biome is recognised from the fog color the game sends to the shader.
   Weights come from fog chromaticity (brightness independent) and blend
   smoothly because the game itself fades the fog color between biomes.
   NL_REF_* are vanilla Bedrock nether fog colors (fogs/*.json):
   if a resource pack changes nether fog, update these values. */
#define NL_REF_NETHER_WASTES   vec3(0.200,0.031,0.031) // #330808 hell
#define NL_REF_CRIMSON_FOREST  vec3(0.200,0.012,0.012) // #330303
#define NL_REF_WARPED_FOREST   vec3(0.102,0.020,0.102) // #1a051a
#define NL_REF_SOULSAND_VALLEY vec3(0.106,0.278,0.271) // #1b4745
#define NL_REF_BASALT_DELTAS   vec3(0.408,0.373,0.439) // #685f70

// grade = tint (multiply), haze color + amount (mix), saturation
#define NL_GRADE_WASTES_TINT   vec3(1.12,0.86,0.62) // orange
#define NL_GRADE_WASTES_HAZE   vec4(0.55,0.22,0.06, 0.06)
#define NL_GRADE_WASTES_SAT    1.08
#define NL_GRADE_CRIMSON_TINT  vec3(1.18,0.72,0.66) // warm red
#define NL_GRADE_CRIMSON_HAZE  vec4(0.55,0.06,0.05, 0.08)
#define NL_GRADE_CRIMSON_SAT   1.12
#define NL_GRADE_WARPED_TINT   vec3(0.72,1.06,1.04) // turquoise
#define NL_GRADE_WARPED_HAZE   vec4(0.05,0.35,0.36, 0.08)
#define NL_GRADE_WARPED_SAT    1.05
#define NL_GRADE_SOUL_TINT     vec3(0.74,0.95,1.18) // cold blue
#define NL_GRADE_SOUL_HAZE     vec4(0.10,0.30,0.45, 0.10)
#define NL_GRADE_SOUL_SAT      0.85
#define NL_GRADE_BASALT_TINT   vec3(0.95,0.94,0.97) // grey haze
#define NL_GRADE_BASALT_HAZE   vec4(0.42,0.40,0.43, 0.22)
#define NL_GRADE_BASALT_SAT    0.55

/* End color grading: purple-dark palette */
#define NL_GRADE_END_TINT      vec3(0.86,0.72,1.08)
#define NL_GRADE_END_HAZE      vec4(0.16,0.04,0.22, 0.10)
#define NL_GRADE_END_SAT       0.9
#define NL_GRADE_END_EXPOSURE  0.88

/* ---------------------------------------------------------------------------
   3. PRESET -> OPTION MAPPING (no need to edit)
--------------------------------------------------------------------------- */

// any per-pixel effect needs world position and geometric normal in fragment
#if TS_WATER_PER_PIXEL || TS_PUDDLES || TS_AO_ON || TS_FACE_SHADING_ON || TS_LAVA_FLOW || (TS_CAUSTICS == 2)
  #define NL_FRAG_FX
#endif

#if TS_WATER_WAVES == 0
  #undef TS_WATER_VERTEX_WAVE
  #define TS_WATER_VERTEX_WAVE 0
#endif

#if !TS_WATER_CLOUD_REFL && !TS_PUDDLE_CLOUD_REFL
  #undef NL_CLOUD_AURORA_REFLECTION
#endif

#if !TS_CAUSTICS
  #undef NL_CAUSTIC_INTENSITY
  #define NL_CAUSTIC_INTENSITY 0.0
#endif

#if !TS_UNDERWATER_DISTORT_ON
  #undef NL_UNDERWATER_WAVE
#endif

#if !TS_PLANTS_WAVE
  #undef NL_PLANTS_WAVE
  #undef NL_LANTERN_WAVE
#endif

#if !TS_GLOW_SHIMMER
  #undef NL_GLOW_SHIMMER
#endif

#if !TS_RAIN_MIST
  #undef NL_RAIN_MIST_OPACITY
#endif

#if !TS_CLOUDY_FOG
  #undef NL_CLOUDY_FOG
#endif

#if !TS_SHOOTING_STAR
  #undef NL_SHOOTING_STAR
#endif

#if !TS_AURORA
  #undef NL_AURORA
#endif

#if NL_CLOUD_TYPE != 1 // TODO (upstream): cloud shadow for other cloud types
  #undef NL_CLOUD_SHADOW
#endif

#endif
