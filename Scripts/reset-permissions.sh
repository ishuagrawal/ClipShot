#!/bin/zsh
set -euo pipefail

/usr/bin/tccutil reset Accessibility com.ishu.ClipShot
/usr/bin/tccutil reset ScreenCapture com.ishu.ClipShot

echo "Reset ClipShot Accessibility and Screen Recording permissions."
echo "Reopen /Applications/ClipShot.app, then grant both permissions again."
