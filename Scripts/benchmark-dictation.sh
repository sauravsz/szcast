#!/bin/bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if (( $# < 1 || $# > 4 )); then
    printf 'Usage: %s AUDIO [HELPER_APP] [MODEL_DIRECTORY] [MODEL]\n' "${0##*/}" >&2
    exit 2
fi
helper=${2:-"$repo/build/DerivedData/Build/Products/Debug/szcast Dev.app/Contents/Helpers/szcast Dev Dictation.app"}
models=${3:-"$HOME/Library/Caches/com.sauravsz.szcast.dev/Dictation"}
binary=$(mktemp /tmp/szcast-dictation-benchmark.XXXXXX)
trap 'rm -f "$binary"' EXIT
swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos26.0" \
    "$repo/Tests/dictation-performance.swift" \
    "$repo/szcast/Platform/ProcessExit.swift" \
    "$repo/szcast/Features/Dictation/Model/DictationModel.swift" \
    "$repo/szcast/Features/Dictation/Service/DictationWire.swift" -o "$binary"
"$binary" "$1" "$helper" "$models" "${4:-all}"
