#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-/private/tmp/ClipShotDerivedData}"
BUILT_APP="$DERIVED_DATA/Build/Products/Debug/ClipShot.app"
INSTALLED_APP="/Applications/ClipShot.app"
REQUIREMENT='designated => identifier "com.ishu.ClipShot"'

xcodebuild \
  -project "$ROOT_DIR/ClipShot.xcodeproj" \
  -scheme ClipShot \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  -r="$REQUIREMENT" \
  "$BUILT_APP"

/usr/bin/codesign --verify --verbose=4 "$BUILT_APP"
/usr/bin/codesign -d -r- "$BUILT_APP"

/usr/bin/ditto "$BUILT_APP" "$INSTALLED_APP"

if /usr/bin/pgrep -x ClipShot >/dev/null; then
  /usr/bin/killall ClipShot
  # Wait for the old instance to fully exit; launching while Launch Services
  # is still tearing it down fails with -600.
  for _ in {1..50}; do
    /usr/bin/pgrep -x ClipShot >/dev/null || break
    sleep 0.1
  done
fi

# Retry: Launch Services can briefly refuse (-600) right after a kill.
for attempt in {1..5}; do
  if /usr/bin/open "$INSTALLED_APP"; then
    exit 0
  fi
  sleep 0.5
done
echo "Failed to launch $INSTALLED_APP" >&2
exit 1
