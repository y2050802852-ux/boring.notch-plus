#!/bin/bash
# Local build script for boringNotch (Release .app).
#
# Disables hardened runtime: the repo default ENABLE_HARDENED_RUNTIME=YES plus
# the local ad-hoc signing (no Team ID) makes macOS library validation reject
# the ad-hoc-resigned embedded MediaRemoteAdapter.framework at launch — dyld
# aborts with "different TeamIdentifiers". Official CI signs with a real
# certificate whose Team ID matches after re-signing, so upstream project
# settings are left untouched; this override is local-only.
#
# Usage: tools/build.sh [extra xcodebuild args...]
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild \
  -project boringNotch.xcodeproj \
  -scheme boringNotch \
  -configuration Release \
  -destination "generic/platform=macOS" \
  ENABLE_HARDENED_RUNTIME=NO \
  "$@"

APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/boringNotch-*/Build/Products/Release/boringNotch.app 2>/dev/null | head -1)

# Sign with the stable development identity when available. TCC grants
# (accessibility, notifications) attach to the code-signing identity, so a
# stable identity keeps them valid across rebuilds — ad-hoc builds lose
# them every time.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "boringNotch Dev"; then
  codesign --force --sign "boringNotch Dev" "$APP" >/dev/null 2>&1 && echo "Signed: boringNotch Dev"
fi

echo
echo "Built: $APP"
