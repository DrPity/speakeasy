#!/usr/bin/env bash
# Compile Speakeasy and package it into a code-signed .app bundle.
# Needs nothing beyond the Command Line Tools (Swift 6.3 + macOS 26 SDK) — Xcode is unnecessary.
set -euo pipefail

cd "$(dirname "$0")"

APP="Speakeasy.app"
BIN="LocalSTT"   # internal executable name; held constant so TCC approvals survive
BUNDLE_ID="com.mschade.localstt"   # held constant so macOS retains previously granted permissions

echo "==> Building (release)..."
swift build -c release

echo "==> Packaging ${APP} ..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp ".build/release/${BIN}" "${APP}/Contents/MacOS/${BIN}"
cp "Info.plist" "${APP}/Contents/Info.plist"
cp "Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"   # regenerate with scripts/make-icon.sh

# Sign using a STABLE identity so macOS retains the Accessibility / Microphone /
# Speech approvals between rebuilds (TCC ties those approvals to the code
# signature; an ad-hoc signature differs on every build, wiping them each time).
#
# Looked up in this order:
#   1. $CODESIGN_IDENTITY when explicitly provided.
#   2. "LocalSTT Self-Signed" when that certificate exists in the keychain
#      (picked up automatically, sparing you the export in every shell).
#   3. Ad-hoc ("-") as a fallback — with a WARNING that approvals vanish on rebuild.
#
# IMPORTANT: the hardened runtime (--options runtime) must stay OFF here. With
# the hardened runtime active, microphone use demands the audio-input
# entitlement; lacking it, AVCaptureDevice.requestAccess fails silently (false,
# no dialog). For a personal, unsandboxed utility the Info.plist usage strings
# suffice on their own — same as the working v1.
SELF_SIGNED="LocalSTT Self-Signed"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    IDENTITY="${CODESIGN_IDENTITY}"
elif security find-identity -p codesigning 2>/dev/null | grep -q "${SELF_SIGNED}"; then
    IDENTITY="${SELF_SIGNED}"
else
    IDENTITY="-"
    echo "WARNING: no stable signing identity available — falling back to ad-hoc signing."
    echo "         Accessibility/Microphone approvals will be dropped by macOS on the next rebuild."
    echo "         Make a self-signed \"${SELF_SIGNED}\" code-signing certificate (refer to the README) to resolve this."
fi

echo "==> Signing (identity: ${IDENTITY})..."
codesign --force --sign "${IDENTITY}" --identifier "${BUNDLE_ID}" "${APP}"

echo "Finished ${APP}"
echo "Start it via:  open ${APP}"
