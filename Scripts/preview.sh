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

mkdir -p "${OUT}"
swiftc -O "${ROOT}/Scripts/preview-harness.swift" "${SOURCES[@]}" -o "${TOOL}"
"${TOOL}" "${OUT}"

echo
echo "Wrote previews to ${OUT}"
