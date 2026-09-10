#!/bin/bash
#
# Regenerates the app icon and the README figures from Scripts/make-assets.swift.
#
# The generator is compiled against Sources/WindowPin/Utilities/PinGlyph.swift so
# the pin in the icon is literally the same path the menu bar draws.
#
# Outputs:
#   Resources/AppIcon.icns      bundled by Scripts/build-app.sh
#   docs/images/*.png           referenced from README.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$(mktemp -d)/make-assets"

echo "==> Compiling generator"
swiftc -O \
  "${ROOT}/Scripts/make-assets.swift" \
  "${ROOT}/Sources/WindowPin/Utilities/PinGlyph.swift" \
  -o "${TOOL}"

echo "==> Rendering"
"${TOOL}" "${ROOT}"

echo "==> Packing AppIcon.icns"
iconutil --convert icns \
  --output "${ROOT}/Resources/AppIcon.icns" \
  "${ROOT}/Resources/AppIcon.iconset"

# The iconset is a build intermediate; only the .icns is bundled.
rm -rf "${ROOT}/Resources/AppIcon.iconset"

echo
echo "Wrote ${ROOT}/Resources/AppIcon.icns"
