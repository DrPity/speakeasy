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

# Vocabulary screen
crop panel-vocabulary        128 504 vocabulary
crop panel-vocabulary        650 612 find-replace
# Animations
cp "${WORK}/anim-overlay.gif" "${OUT}/overlay.gif"
cp "${WORK}/anim-glass.gif" "${OUT}/glass.gif"
cp "${WORK}/anim-menubar.gif" "${OUT}/menubar.gif"

echo "Wrote $(ls "${OUT}" | wc -l | tr -d ' ') images to ${OUT}/"
