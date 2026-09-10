#!/bin/bash
#
# Builds, verifies, notarizes and publishes a release.
#
# Every step that can silently produce a broken download is a gate that stops
# the script. This exists because doing it by hand shipped two bad builds:
# one that was never notarized (macOS refused to open it) and one that aborted
# the moment a video was dropped in, because AVKit was not linked. Neither
# failed at compile time.
#
# Usage:
#   ./Scripts/release.sh 1.0.1              publish
#   ./Scripts/release.sh 1.0.1 --dry-run    build and verify, publish nothing
#
# Requires: a Developer ID certificate, notarytool credentials stored as
# `xcrun notarytool store-credentials "windowpin"`, and gh authenticated.
#
set -euo pipefail

VERSION="${1:-}"
DRY_RUN="${2:-}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-windowpin}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_REPO="${SITE_REPO:-$HOME/Documents/landing-page-app-window-pin}"
SITE_URL="https://andrew2722.github.io/landing-page-app-window-pin"
APP="${ROOT}/build/WindowPin.app"
ZIP="${ROOT}/build/WindowPin.zip"
BIN="${APP}/Contents/MacOS/WindowPin"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFAILED: %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '    ok  %s\n' "$1"; }

[[ -n "${VERSION}" ]] || fail "usage: ./Scripts/release.sh <version> [--dry-run]"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.2.3, got '${VERSION}'"

# ---------------------------------------------------------------- preflight
step "Preflight"
command -v gh >/dev/null || fail "gh is not installed"
xcrun notarytool history --keychain-profile "${KEYCHAIN_PROFILE}" >/dev/null 2>&1 \
  || fail "no notarytool credentials for profile '${KEYCHAIN_PROFILE}'. Run:
    xcrun notarytool store-credentials \"${KEYCHAIN_PROFILE}\" --apple-id <id> --team-id <team>"
ok "notarytool credentials"
[[ -d "${SITE_REPO}" ]] || fail "landing repo not found at ${SITE_REPO}"
ok "landing repo at ${SITE_REPO}"

# Publishing whatever happens to be in the working tree is how unfinished work
# reaches users. Commit first, deliberately.
if [[ -n "$(cd "${ROOT}" && git status --porcelain)" ]] && [[ "${DRY_RUN}" != "--dry-run" ]]; then
  (cd "${ROOT}" && git status --short | head -10)
  fail "the app repo has uncommitted changes — commit or stash them, then release"
fi
ok "working tree is clean"

# ------------------------------------------------------------------- build
step "Building ${VERSION}"
VERSION="${VERSION}" "${ROOT}/Scripts/build-app.sh" >/dev/null || fail "build failed"
[[ -x "${BIN}" ]] || fail "no binary at ${BIN}"
ok "built and signed"

# A Swift `import` does not reliably link a framework, and the failure only
# appears at runtime when the view is first constructed. Check the binary.
step "Verifying framework linkage"
for fw in AVKit AVFoundation PDFKit WebKit ScreenCaptureKit; do
  otool -L "${BIN}" | grep -q "/${fw}.framework/" || fail "${fw} is not linked — a view using it will abort at runtime"
  ok "${fw}"
done

# ------------------------------------------------------------ smoke launch
step "Smoke test: launch and confirm it stays up"
CRASH_DIR="${HOME}/Library/Logs/DiagnosticReports"
BEFORE="$(ls "${CRASH_DIR}" 2>/dev/null | grep -c '^WindowPin-' || true)"
"${BIN}" >/dev/null 2>&1 &
SMOKE_PID=$!
sleep 4
if ! kill -0 "${SMOKE_PID}" 2>/dev/null; then
  fail "the app exited on its own within 4s — check ${CRASH_DIR}"
fi
kill "${SMOKE_PID}" 2>/dev/null || true
wait "${SMOKE_PID}" 2>/dev/null || true
sleep 1
AFTER="$(ls "${CRASH_DIR}" 2>/dev/null | grep -c '^WindowPin-' || true)"
[[ "${AFTER}" -eq "${BEFORE}" ]] || fail "a crash report appeared during the smoke test"
ok "stayed running, no crash report"

# --------------------------------------------------------------- notarize
step "Notarizing (this waits for Apple)"
SUBMIT_ZIP="${ROOT}/build/WindowPin-submit.zip"
rm -f "${SUBMIT_ZIP}"
ditto -c -k --keepParent "${APP}" "${SUBMIT_ZIP}"
# Upload and wait are separated on purpose. `--wait` folds them together, so a
# dropped connection while waiting (HTTPClientError.connectTimeout) throws away
# a submission that was uploaded fine and is already being processed.
xcrun notarytool submit "${SUBMIT_ZIP}" --keychain-profile "${KEYCHAIN_PROFILE}" --no-wait 2>&1 \
  | tee /tmp/notary.log | tail -3
SUBMISSION_ID="$(sed -n 's/^ *id: \(.*\)$/\1/p' /tmp/notary.log | head -1)"
[[ -n "${SUBMISSION_ID}" ]] || fail "no submission id returned — see /tmp/notary.log"
ok "uploaded as ${SUBMISSION_ID}"

NOTARY_STATUS=""
for attempt in $(seq 1 60); do
  sleep 10
  # A transient failure here costs one poll, not the release.
  INFO="$(xcrun notarytool info "${SUBMISSION_ID}" --keychain-profile "${KEYCHAIN_PROFILE}" 2>&1 || true)"
  NOTARY_STATUS="$(sed -n 's/^ *status: \(.*\)$/\1/p' <<<"${INFO}" | head -1)"
  case "${NOTARY_STATUS}" in
    Accepted) break ;;
    Invalid|Rejected)
      xcrun notarytool log "${SUBMISSION_ID}" --keychain-profile "${KEYCHAIN_PROFILE}" 2>&1 | head -40
      fail "Apple rejected the build (${NOTARY_STATUS})" ;;
    *) printf '    %s (%d/60)\n' "${NOTARY_STATUS:-waiting}" "${attempt}" ;;
  esac
done
[[ "${NOTARY_STATUS}" == "Accepted" ]] || fail "notarization did not finish in 10 minutes (id ${SUBMISSION_ID})"
ok "accepted"

# Staple in a scratch directory and copy back. Stapling in place inside the
# build directory fails with "Could not remove existing ticket ... No such file
# or directory" (error 73), while the identical bundle staples fine elsewhere.
# Apple also publishes the ticket slightly after accepting, so retry.
STAGE="$(mktemp -d)"
ditto "${APP}" "${STAGE}/WindowPin.app"
STAPLED=0
for attempt in $(seq 1 8); do
  if xcrun stapler staple "${STAGE}/WindowPin.app" >/dev/null 2>&1; then STAPLED=1; break; fi
  printf '    ticket not ready, retrying (%d/8)\n' "${attempt}"
  sleep 15
done
[[ "${STAPLED}" -eq 1 ]] || fail "could not staple the ticket after 8 attempts"
xcrun stapler validate "${STAGE}/WindowPin.app" >/dev/null || fail "stapled ticket does not validate"
rm -rf "${APP}"
ditto "${STAGE}/WindowPin.app" "${APP}"
rm -rf "${STAGE}"
ok "ticket stapled (opens offline)"

# ------------------------------------------------------- gatekeeper as user
# The decisive check: pretend to be someone who downloaded it in a browser.
step "Gatekeeper check, as a downloader sees it"
rm -f "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"
GK_DIR="$(mktemp -d)"
ditto -x -k "${ZIP}" "${GK_DIR}"
xattr -w com.apple.quarantine "0083;00000000;Safari;" "${GK_DIR}/WindowPin.app"
spctl -a -vvv -t install "${GK_DIR}/WindowPin.app" 2>&1 | grep -q "accepted" \
  || fail "Gatekeeper rejects the download — do not publish this"
rm -rf "${GK_DIR}"
ok "accepted by Gatekeeper with the quarantine flag set"

SIZE_MB="$(echo "scale=1; $(stat -f%z "${ZIP}") / 1048576" | bc)"
ok "artifact: ${SIZE_MB} MB"

if [[ "${DRY_RUN}" == "--dry-run" ]]; then
  step "Dry run — nothing published"
  echo "    would publish ${VERSION} (${SIZE_MB} MB) to the release and ${SITE_URL}"
  exit 0
fi

# --------------------------------------------------------------- publish
step "Publishing to the landing page"
cp "${ZIP}" "${SITE_REPO}/WindowPin.zip"
# Keep the caption honest; a stale version or size is a small lie on the page.
/usr/bin/sed -i '' -E \
  "s#Version [0-9]+\.[0-9]+\.[0-9]+ · [0-9.]+ MB#Version ${VERSION} · ${SIZE_MB} MB#" \
  "${SITE_REPO}/index.html"
grep -q "Version ${VERSION} · ${SIZE_MB} MB" "${SITE_REPO}/index.html" \
  || fail "could not update the version caption in index.html"
ok "caption now reads ${VERSION} · ${SIZE_MB} MB"

(cd "${SITE_REPO}" && git add -A && git commit -q -m "release: ${VERSION}" && git push -q origin main)
ok "landing page pushed"

step "Publishing the GitHub release"
(cd "${ROOT}" && git push -q origin main)
if gh release view "v${VERSION}" >/dev/null 2>&1; then
  gh release upload "v${VERSION}" "${ZIP}" --clobber >/dev/null
else
  gh release create "v${VERSION}" "${ZIP}" --title "Window Pin ${VERSION}" \
    --notes "Signed with a Developer ID and notarized by Apple.

Requires macOS 14 or later.

Download and install instructions: ${SITE_URL}" >/dev/null
fi
ok "release v${VERSION} published"

# ------------------------------------------------------------- verify live
step "Verifying the live download"
LOCAL_SHA="$(shasum -a 256 "${ZIP}" | cut -d' ' -f1)"
for attempt in $(seq 1 12); do
  sleep 15
  SERVED_SHA="$(curl -sL "${SITE_URL}/WindowPin.zip" | shasum -a 256 | cut -d' ' -f1)"
  if [[ "${SERVED_SHA}" == "${LOCAL_SHA}" ]]; then
    ok "the site serves this exact build"
    printf '\n\033[32mReleased %s\033[0m  →  %s\n' "${VERSION}" "${SITE_URL}"
    exit 0
  fi
  printf '    waiting for GitHub Pages to update (%d/12)\n' "${attempt}"
done
fail "the site is still serving an older build — check the Pages deployment"
