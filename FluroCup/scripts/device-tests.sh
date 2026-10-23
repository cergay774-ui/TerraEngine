#!/usr/bin/env bash
# Runs the engine's on-device tests on the emulator and prints what explains a failure.
set -u
adb logcat -c || true
./gradlew --no-daemon --stacktrace :core-engine:connectedDebugAndroidTest
status=$?
echo "===== app log ====="
adb logcat -d -v brief | grep -E "PreviewDeviceTest|PreviewEngine|ShaderEffect|E/ExoPlayerImplInternal|E/CompositionPlayer|E/TransformerInternal|E/Transformer|VideoFrameProcessor|E/MediaCodec" | tail -n 150
echo "===== test failures ====="
find core-engine/build/outputs/androidTest-results -name '*.xml' -exec grep -h -A 40 "<failure" {} + | head -n 200
exit $status
