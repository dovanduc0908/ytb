#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
serial="${1:?Usage: scripts/test-android.sh SERIAL}"
cd apps/native
flutter test integration_test/player_test.dart -d "$serial" --no-uninstall --reporter expanded | tee ../../artifacts/qa/integration.log
cd ../..
python3 - <<'PYREPORT'
import json
from pathlib import Path
lines=Path('artifacts/qa/integration.log').read_text().splitlines()
line=next(x for x in lines if 'YTB_QA_JSON:' in x)
data=json.loads(line.split('YTB_QA_JSON:',1)[1])
Path('artifacts/qa/player-qa.json').write_text(json.dumps(data,indent=2))
PYREPORT
./scripts/build-android.sh
./scripts/install-android.sh "$serial"
