#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
serial="${1:?Usage: scripts/test-android.sh SERIAL}"
mkdir -p artifacts/qa
# Always restore the normal app, including when an integration assertion fails.
restore_app() {
  local result=$?
  trap - EXIT
  cd "${YTB_PROJECT_ROOT}"
  if bash scripts/build-android.sh && bash scripts/install-android.sh "$serial"; then
    exit "$result"
  else
    print -u2 'Could not restore the normal APK after device tests.'
    exit 1
  fi
}
YTB_PROJECT_ROOT="$PWD"
trap restore_app EXIT
cd apps/native
for target in public_youtube_policy facebook_quality_ui; do
  flutter test "integration_test/${target}_test.dart" -d "$serial" --no-uninstall --reporter expanded | tee "../../artifacts/qa/${target}.log"
done
