#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
serial="${1:?Usage: scripts/test-orientation.sh SERIAL}"
qa_dir="${YTB_QA_DIR:-/tmp/ytb-orientation-qa}"
mkdir -p "$qa_dir"
# FFmpeg from an existing installation or imageio-ffmpeg's bundled executable.
qa_ffmpeg="${FFMPEG:-$(command -v ffmpeg || true)}"
if [ -z "$qa_ffmpeg" ]; then
  echo 'Set FFMPEG to a local FFmpeg executable.' >&2
  exit 1
fi
for orientation in landscape portrait; do
  size=640x360
  [ "$orientation" != portrait ] || size=360x640
  "$qa_ffmpeg" -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=$size:rate=15" -f lavfi -i sine=frequency=440:sample_rate=44100 -t 5 -c:v libx264 -crf 35 -pix_fmt yuv420p -c:a aac -b:a 32k -movflags +faststart "$qa_dir/$orientation.mp4"
done
cd apps/native
flutter build apk --debug --target-platform android-arm64
adb -s "$serial" install -r build/app/outputs/flutter-apk/app-debug.apk
for orientation in landscape portrait; do
  adb -s "$serial" shell "run-as com.duchaik.ytb sh -c 'cat > cache/qa-$orientation.mp4'" < "$qa_dir/$orientation.mp4"
done
flutter test integration_test/orientation_reliability_test.dart -d "$serial" --no-uninstall --reporter expanded | tee "$qa_dir/device.log"
adb -s "$serial" exec-out run-as com.duchaik.ytb cat cache/orientation-reliability.json > "$qa_dir/results.json"
