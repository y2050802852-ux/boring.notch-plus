#!/bin/bash
# SPM type-check harness for boringNotch (no full Xcode required).
#
# 1. Mirrors boringNotch/ Swift sources into tools/harness/boringNotch/ with all
#    #Preview macro blocks stripped (the Xcode-only PreviewsMacros plugin does
#    not exist in the Command Line Tools toolchain).
# 2. Adds stubs for asset-catalog-generated symbols (ImageResource members and
#    Bundle.module) that Xcode generates at build time from Assets.xcassets.
# 3. Runs `swift build` against the mirror. Sources under boringNotch/ are
#    never modified.
#
# Usage: tools/typecheck.sh [extra swift build args...]
set -euo pipefail
cd "$(dirname "$0")/.."

MIRROR=tools/harness/boringNotch

rsync -a --delete \
  --include='*/' --include='*.swift' --exclude='*' \
  boringNotch/ "$MIRROR/"

cat > "$MIRROR/HarnessAssetStubs.swift" << 'SWIFT'
import AppKit
import SwiftUI

// Harness-only stubs for symbols Xcode generates from Assets.xcassets.
extension Bundle {
    static var module: Bundle { .main }
}

extension ImageResource {
    static let bolt = ImageResource(name: "bolt", bundle: .module)
    static let chrome = ImageResource(name: "chrome", bundle: .module)
    static let defaultmusic = ImageResource(name: "defaultmusic", bundle: .module)
    static let github = ImageResource(name: "Github", bundle: .module)
    static let logo = ImageResource(name: "logo", bundle: .module)
    static let logo2 = ImageResource(name: "logo2", bundle: .module)
    static let plug = ImageResource(name: "plug", bundle: .module)
    static let sparkle = ImageResource(name: "sparkle", bundle: .module)
    static let spotlight = ImageResource(name: "spotlight", bundle: .module)
    static let theboringteam = ImageResource(name: "theboringteam", bundle: .module)
}
SWIFT

PYTHON=/opt/miniconda3/bin/python3
command -v "$PYTHON" >/dev/null 2>&1 || PYTHON=python3

find "$MIRROR" -name '*.swift' -not -name 'HarnessAssetStubs.swift' -print0 | \
  xargs -0 "$PYTHON" tools/strip_previews.py | grep -v "removed 0" || true

swift build "$@"
