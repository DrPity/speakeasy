#!/usr/bin/env bash
# Regenerate the README's feature images in docs/images/ from real renders of
# the app (debug build, `LocalSTT --snapshot`, sample data, no permissions).
# Crops are pixel offsets into the 2× renders; adjust them if a screen's
# layout changes. Run after UI changes, review the diff, commit.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="docs/images"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

./scripts/swiftw build -c debug
.build/debug/LocalSTT --snapshot "${WORK}"
mkdir -p "${OUT}"

# crop <render> <y> <height> <name>: full panel width, 16 px side margins kept.
crop() {
    sips -c "$3" 728 --cropOffset "$2" 16 "${WORK}/$1.png" --out "${OUT}/$4.png" >/dev/null
}

# Main panel
crop panel-ready             160 158 talk-key
crop panel-ready             330 115 microphone
crop panel-ready             712 278 recent
# Preferences
crop panel-settings          166 178 hold-or-toggle
crop panel-settings          349 162 escape
crop panel-settings          722 318 hover-help
crop panel-settings         1335 135 language
crop panel-settings         1470  96 login
# Vocabulary
crop panel-vocabulary        128 504 vocabulary
crop panel-vocabulary        650 612 find-replace
# First run
cp "${WORK}/panel-onboarding-step1.png" "${OUT}/first-run.png"
crop panel-onboarding-step1  780 180 private
# Overlay and animations
cp "${WORK}/hud-3-no-audio.png" "${OUT}/no-audio.png"
cp "${WORK}/anim-overlay.gif" "${OUT}/overlay.gif"
cp "${WORK}/anim-glass.gif" "${OUT}/glass.gif"
cp "${WORK}/anim-menubar.gif" "${OUT}/menubar.gif"
# Typing into another app: a still from the demo GIF (marketing/gifs).
sips -Z 1200 marketing/gifs/dictation-demo/final/stills/04-typed-into-the-note.png --out "${OUT}/types-anywhere.png" >/dev/null

echo "Wrote $(ls "${OUT}" | wc -l | tr -d ' ') images to ${OUT}/"
