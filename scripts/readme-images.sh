#!/usr/bin/env bash
# Regenerate the README's feature cards in docs/images/ from real renders of
# the app (debug build, `LocalSTT --snapshot`, sample data, no permissions).
# The cards are composed in SnapshotRenderer.swift (renderFeatureCards).
# Run after UI changes, review the diff, commit.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="docs/images"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

./scripts/swiftw build -c debug
.build/debug/LocalSTT --snapshot "${WORK}"

rm -rf "${OUT}"
mkdir -p "${OUT}"
cp "${WORK}"/card-*.png "${WORK}"/card-*.gif "${OUT}/"

echo "Wrote $(ls "${OUT}" | wc -l | tr -d ' ') cards to ${OUT}/ ($(du -sh "${OUT}" | cut -f1))"
