#!/bin/bash
#
# Assembles Sources/ into build/WindowPin.app.
#
# SwiftPM produces a bare executable, but Accessibility permission is granted to
# an *application bundle* with a code signature, so the binary has to be wrapped
# in a signed .app before macOS will let it move other apps' windows.
#
# Environment:
#   CONFIGURATION      debug | release            (default: release)
#   CODESIGN_IDENTITY  signing identity           (default: "-", ad-hoc)
#   UNIVERSAL          1 to build arm64 + x86_64  (default: native only)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"

# Pick a real signing identity when one exists.
#
# This matters more than it looks: an ad-hoc signature's designated requirement
# is the binary's cdhash, so every rebuild produces a "different app" and macOS
# silently drops the Accessibility permission — the app then reports "not
# trusted" even though the switch in System Settings is still on. A certificate
# gives a team-based requirement that survives rebuilds.
find_identity() {
  local pattern="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n "s/.*\"\(${pattern}[^\"]*\)\".*/\1/p" \
    | head -1
}

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  CODESIGN_IDENTITY="$(find_identity 'Developer ID Application')"
  [[ -z "${CODESIGN_IDENTITY}" ]] && CODESIGN_IDENTITY="$(find_identity 'Apple Development')"
  [[ -z "${CODESIGN_IDENTITY}" ]] && CODESIGN_IDENTITY="-"
fi
APP_NAME="WindowPin"
BUNDLE_ID="com.windowpin.app"
# Overridable so Scripts/release.sh can stamp the version it is publishing.
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="1"

ICON_SRC="${ROOT}/Resources/AppIcon.icns"

APP_DIR="${ROOT}/build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"

echo "==> Compiling (${CONFIGURATION})"
BUILD_ARGS=(--configuration "${CONFIGURATION}" --package-path "${ROOT}")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"

BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "error: executable not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${CONTENTS}/Resources"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"

# Without an icon the app shows the generic blank document tile everywhere it
# appears — Finder, the Accessibility and Screen Recording lists in System
# Settings, and the permission prompts themselves. Regenerate with
# ./Scripts/make-assets.sh if it is missing.
if [[ -f "${ICON_SRC}" ]]; then
  cp "${ICON_SRC}" "${CONTENTS}/Resources/AppIcon.icns"
else
  echo "warning: ${ICON_SRC} not found; bundle will have no icon" >&2
fi

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Window Pin</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Window Pin</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "==> Signing with identity: ${CODESIGN_IDENTITY}"
SIGN_ARGS=(--force --sign "${CODESIGN_IDENTITY}")
if [[ "${CODESIGN_IDENTITY}" != "-" ]]; then
  # Hardened runtime is required for notarization and only makes sense with a
  # real identity; ad-hoc builds stay unhardened so they keep launching locally.
  SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "${APP_DIR}"
codesign --verify --verbose=1 "${APP_DIR}"

# Launch Services caches a bundle's icon by path. Without this, a bundle that
# was ever built without an icon keeps showing the blank generic tile in Finder
# and in the System Settings permission lists no matter how many times it is
# rebuilt.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -f "${APP_DIR}" || true
  touch "${APP_DIR}"
fi

echo
echo "Built ${APP_DIR}"
echo "Run it with:  open '${APP_DIR}'"
