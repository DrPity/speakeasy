#!/usr/bin/env bash
# Execute the test suite.
#
# With full Xcode present, `swift test` works as-is. On a machine carrying only
# the Command Line Tools, swift-testing lives somewhere the compiler and
# dynamic loader never look by default; those locations are appended here
# instead of baking machine-specific flags into Package.swift.
set -euo pipefail

cd "$(dirname "$0")/.."

CLT_FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
CLT_LIB="$(xcode-select -p)/Library/Developer/usr/lib"

ARGS=()
if [[ -d "${CLT_FRAMEWORKS}/Testing.framework" ]]; then
    ARGS+=(-Xswiftc -F -Xswiftc "${CLT_FRAMEWORKS}")
    ARGS+=(-Xlinker -rpath -Xlinker "${CLT_FRAMEWORKS}")
fi
if [[ -f "${CLT_LIB}/lib_TestingInterop.dylib" ]]; then
    ARGS+=(-Xlinker -rpath -Xlinker "${CLT_LIB}")
fi

exec ./scripts/swiftw test "${ARGS[@]+"${ARGS[@]}"}" "$@"
