#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'iOS compilation requires a Mac with Xcode 27.1 or later.' >&2
  exit 1
fi
python3 scripts/check_ios_project.py
python3 - <<'PY'
import re, subprocess
text = subprocess.check_output(['xcodebuild', '-version'], text=True)
match = re.search(r'Xcode (\d+)(?:\.(\d+))?', text)
if not match or (int(match[1]), int(match[2] or 0)) < (27, 1):
    raise SystemExit('Select Xcode 27.1 or later with the iOS 27 SDK before building.')
print(text)
PY
export CI=true BOT=true FLUTTER_SUPPRESS_ANALYTICS=true
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build ios --release --no-codesign --no-pub
python3 scripts/package_unsigned_ipa.py
