#!/bin/bash
#
# Renders the interface to PNGs for visual review.
#
# Compiles Scripts/preview-harness.swift against the app's own view sources —
# minus App/WindowPinApp.swift, whose @main would collide with the harness's —
# so the screenshots always show the code that actually ships.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-${ROOT}/build/preview}"
TOOL="$(mktemp -d)/preview-harness"

SOURCES=()
while IFS= read -r file; do
  [[ "${file}" == *"/App/WindowPinApp.swift" ]] && continue
  SOURCES+=("${file}")
done < <(find "${ROOT}/Sources/WindowPin" -name '*.swift' | sort)

# The harness is a bare executable, not a bundle, so Sparkle has to be found
# where SwiftPM unpacked it rather than in Contents/Frameworks. `UpdateService`
# is compiled in with everything else because `ControllerView` names its type;
# with no Info.plist to read a feed from it simply does nothing here.
SPARKLE_DIR="$(dirname "$(/usr/bin/find "${ROOT}/.build/artifacts" -type d -name 'Sparkle.framework' -path '*macos-*' -print -quit)")"
[[ -d "${SPARKLE_DIR}" ]] || { echo "error: Sparkle not resolved — run 'swift package resolve'" >&2; exit 1; }

mkdir -p "${OUT}"
swiftc -D PREVIEW -O "${ROOT}/Scripts/preview-harness.swift" "${SOURCES[@]}" \
  -F "${SPARKLE_DIR}" -framework Sparkle \
  -Xlinker -rpath -Xlinker "${SPARKLE_DIR}" \
  -o "${TOOL}"
"${TOOL}" "${OUT}"

echo
echo "Wrote previews to ${OUT}"
