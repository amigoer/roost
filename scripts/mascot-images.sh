#!/bin/bash
# Regenerates docs/mascot/*.png from the app's own grid. Run it whenever a face
# is added or its art changes.
#
#   scripts/mascot-images.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# The exporter needs the app's own art, so it is compiled against every source
# in the app target except its entry point, which it replaces.
sources=$(find "$root/Sources/RoostApp" -name '*.swift' ! -name 'main.swift')

swift build --package-path "$root/Packages/RoostCore" -c release >/dev/null
built="$(swift build --package-path "$root/Packages/RoostCore" -c release --show-bin-path)"

# shellcheck disable=SC2086
swiftc -swift-version 6 -suppress-warnings \
    -I "$built/Modules" \
    -o "$build/export-mascot" \
    $sources "$root/scripts/export-mascot.swift" "$built"/RoostCore.build/*.o

mkdir -p "$root/docs/mascot"
"$build/export-mascot" "$root/docs/mascot"
