#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
YTB_SERIAL="${1:?Pass the device serial shown by adb devices -l}"
YTB_APK="${2:-apps/native/build/app/outputs/flutter-apk/app-debug.apk}"
adb -s "$YTB_SERIAL" install -r "$YTB_APK"
adb -s "$YTB_SERIAL" shell am start -n com.duchaik.ytb/.MainActivity
