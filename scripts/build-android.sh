#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
cd apps/native
flutter build apk --debug --target-platform android-arm64
