#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
cd apps/native
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
