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
#   SU_FEED_URL        appcast the app checks       (default: the download page)
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
# Otherwise take the latest tag: the app shows its version in the controller,
# and a hardcoded default meant every development build claimed 1.0.0 no matter
# how far ahead the source was.
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(git -C "${ROOT}" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
  VERSION="${VERSION:-0.0.0}"
fi
# Sparkle decides whether a build is newer by comparing CFBundleVersion, so a
# constant here would make every release look identical to the one installed
# and no update would ever be offered. Tracking the marketing version keeps the
# two in step and keeps the comparison meaningful.
BUILD_NUMBER="${VERSION}"

# Where the app looks for new versions, and the key it checks them against.
#
# The public half of the EdDSA pair belongs in the bundle; the private half
# lives in the login keychain (created by Sparkle's generate_keys) and is what
# Scripts/release.sh uses to sign each build. An update that does not verify
# against this key is refused, so a compromised download page cannot push code
# to anyone who already has the app.
SU_FEED_URL="${SU_FEED_URL:-https://andrew2722.github.io/landing-page-app-window-pin/appcast.xml}"
SU_PUBLIC_KEY="NPEZ4/4Sb/Br15YhOkwogP70Okyf3cd1fjkZ6VJ55DU="

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

# Sparkle travels inside the bundle: it is not just a library but a helper app
# and two XPC services that do the actual replacing, and they have to be next
# to the app they update. The executable finds it through the
# @executable_path/../Frameworks rpath set in Package.swift.
SPARKLE_FW="$(/usr/bin/find "${ROOT}/.build/artifacts" -type d -name 'Sparkle.framework' -path '*macos-*' -print -quit 2>/dev/null || true)"
if [[ -z "${SPARKLE_FW}" ]]; then
  echo "error: Sparkle.framework not found under .build/artifacts — run 'swift package resolve'" >&2
  exit 1
fi
mkdir -p "${CONTENTS}/Frameworks"
# ditto, not cp: a framework is a tree of symlinks (Versions/Current, and the
# top-level entries pointing into it) and copying it flat breaks loading.
ditto "${SPARKLE_FW}" "${CONTENTS}/Frameworks/Sparkle.framework"

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
	<key>SUFeedURL</key>
	<string>${SU_FEED_URL}</string>
	<key>SUPublicEDKey</key>
	<string>${SU_PUBLIC_KEY}</string>
	<!-- Check and install without asking. Someone who installed a menu bar
	     utility months ago will not go looking for a download page, and the
	     alternative to installing quietly is them running an old build for
	     ever. -->
	<key>SUEnableAutomaticChecks</key>
	<true/>
	<key>SUAutomaticallyUpdate</key>
	<true/>
	<key>SUScheduledCheckInterval</key>
	<integer>86400</integer>
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
# Nested code is signed first and the bundle last, because signing a bundle
# seals the hashes of everything inside it — re-signing an inner component
# afterwards invalidates the outer signature. `--deep` would do this in one
# call but Apple has deprecated it and it applies the wrong flags to helper
# apps, so each piece is named explicitly.
SPARKLE_IN_APP="${CONTENTS}/Frameworks/Sparkle.framework"
for nested in \
  "${SPARKLE_IN_APP}/Versions/B/XPCServices/Downloader.xpc" \
  "${SPARKLE_IN_APP}/Versions/B/XPCServices/Installer.xpc" \
  "${SPARKLE_IN_APP}/Versions/B/Updater.app" \
  "${SPARKLE_IN_APP}/Versions/B/Autoupdate" \
  "${SPARKLE_IN_APP}"; do
  [[ -e "${nested}" ]] || { echo "error: missing ${nested}" >&2; exit 1; }
  codesign "${SIGN_ARGS[@]}" "${nested}"
done

codesign "${SIGN_ARGS[@]}" "${APP_DIR}"
codesign --verify --verbose=1 "${APP_DIR}"
# --deep on *verification* is not deprecated and is the only way to catch a
# nested component that was left unsigned or signed with the wrong identity —
# which notarization would otherwise reject minutes later.
codesign --verify --deep --strict --verbose=1 "${APP_DIR}"

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
