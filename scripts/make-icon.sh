#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from Resources/AppIcon.svg.
# Run after editing the SVG; build.sh only copies the committed .icns.
set -euo pipefail

cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

swift scripts/make-icon.swift Resources/AppIcon.svg "${WORK}/AppIcon.iconset"
iconutil --convert icns --output Resources/AppIcon.icns "${WORK}/AppIcon.iconset"
echo "Wrote Resources/AppIcon.icns"
