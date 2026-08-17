#!/bin/bash
# run.sh <shotname> [settle seconds] — build, install, launch, verify, screenshot
set -e
DEV=9125A1C8-C8AC-403C-BB8F-2707AA179DEA
BID=studio.molly.AegirDemo
cd "$(dirname "$0")/AegirDemo"

xcodebuild -project AegirDemo.xcodeproj -scheme AegirDemo -sdk iphonesimulator \
  -destination "id=$DEV" -derivedDataPath build build 2>&1 \
  | grep -E "error:|BUILD" | head -20

APP=build/Build/Products/Debug-iphonesimulator/AegirDemo.app
xcrun simctl terminate "$DEV" "$BID" 2>/dev/null || true
xcrun simctl install "$DEV" "$APP"
xcrun simctl privacy "$DEV" grant location "$BID" 2>/dev/null || true
xcrun simctl location "$DEV" set 51.5074,-0.1278 2>/dev/null || true
xcrun simctl launch "$DEV" "$BID" >/dev/null
sleep "${2:-5}"

OUT="../shots/$1"
xcrun simctl io "$DEV" screenshot "$OUT" 2>/dev/null

# the globe is dark; the home screen is bright — catch a failed launch early
B=$(../venv/bin/python -c "
from PIL import Image; import numpy as np
print(round(float(np.asarray(Image.open('$OUT').convert('RGB')).mean()),1))")
if (( $(echo "$B > 60" | bc -l) )); then
  echo "WARNING: app does not appear to be foreground (brightness $B) — likely home screen"
else
  echo "app foreground OK (brightness $B)"
fi
echo "shot: $OUT"
