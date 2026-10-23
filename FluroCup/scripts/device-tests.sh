#!/usr/bin/env bash
# Runs the engine's on-device tests on the emulator and prints the relevant log lines either way.
set -u
adb logcat -c || true
./gradlew --no-daemon --stacktrace :core-engine:connectedDebugAndroidTest
status=$?
echo "===== logcat ====="
adb logcat -d -v brief | grep -E "PreviewDeviceTest|PreviewEngine|ShaderEffect|TestRunner|AndroidRuntime|VideoFrameProcessor|CompositionPlayer|MediaCodec.*rror|ExoPlayerImpl|E/" | tail -n 400
exit $status
