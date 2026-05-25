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
fi

/usr/bin/open "$INSTALLED_APP"
