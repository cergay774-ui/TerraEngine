#ifndef TIME_H
#define TIME_H

/*
  Stable animation time and world-locked coordinates.

  TIME
  - Source: ViewPositionAndTime.w - the game render timer in seconds. It is
    independent of FPS (not a frame counter), so animation speed never
    depends on frame rate.
  - Problem: the timer grows forever. sin(speed*t) with a large t loses
    float precision (waves start to jerk / "speed up" after hours).
  - Fix: wrap time every NL_TIME_LOOP seconds (highp, before any other math)
    and snap every angular frequency to a whole number of cycles per loop
    with NL_SNAP_W(). Then sin(NL_SNAP_W(w)*t) has the same value right
    before and right after the wrap, so the wrap is invisible.
  - Scrolling patterns use nlScroll(): an offset that also wraps exactly.

  WORLD POSITION
  - CameraPosition is a float; at large coordinates (worldPos + camera)
    loses precision and effects swim or get blocky.
  - Fix: chunk vertices come with a_position relative to the render chunk
    origin. The origin itself is an integer, so it is rounded (killing float
    error), wrapped by NL_WORLD_WRAP and the precise local position is added
    back. All world-space patterns are made exactly periodic with period
    NL_WORLD_WRAP (NL_SNAP_K for sine frequencies, nlNoiseP for noise), so
    the wrap is seamless. Effects are attached to the world, not the camera.
*/

#define NL_TAU 6.2831853

// snap angular frequency (rad/s) to a whole number of cycles per NL_TIME_LOOP
#define NL_SNAP_W(w) (floor((w)*(NL_TIME_LOOP/NL_TAU) + 0.5)*(NL_TAU/NL_TIME_LOOP))

// snap frequency (cycles/s) to a whole number of cycles per NL_TIME_LOOP
#define NL_SNAP_F(f) (floor((f)*NL_TIME_LOOP + 0.5)/NL_TIME_LOOP)

// snap spatial angular frequency (rad/block) to a whole number of cycles per NL_WORLD_WRAP
#define NL_SNAP_K(k) (floor((k)*(NL_WORLD_WRAP/NL_TAU) + 0.5)*(NL_TAU/NL_WORLD_WRAP))

highp float nlWrapTime(highp float rawTime) {
  return mod(rawTime, NL_TIME_LOOP);
}

// offset that moves `speed` units/s and wraps every `period` units, seamless at time wrap
// (speed is snapped so that speed*NL_TIME_LOOP is a whole number of periods)
highp float nlScroll(highp float t, float speed, float period) {
  float cyclesPerLoop = floor(abs(speed)*NL_TIME_LOOP/period + 0.5);
  return sign(speed)*period*fract(t*cyclesPerLoop/NL_TIME_LOOP);
}

// precise world-locked position, x/z wrapped to [0, NL_WORLD_WRAP)
// worldPos: camera relative vertex position, camPos: CameraPosition.xyz, cPos: a_position (chunk local)
highp vec3 nlWrappedWorldPos(highp vec3 worldPos, highp vec3 camPos, highp vec3 cPos) {
  highp vec3 origin = floor(worldPos + camPos - cPos + 0.5);
  origin.xz = mod(origin.xz, vec2_splat(NL_WORLD_WRAP));
  return origin + cPos;
}

#endif
