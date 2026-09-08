#!/bin/bash
# Regenerates docs/settings.png and docs/settings.zh-CN.md's image from the
# real settings view. Run it whenever a switch is added, removed or reworded.
#
#   scripts/settings-screenshots.sh 0.2.0
set -euo pipefail

version="${1:?usage: settings-screenshots.sh <version shown in the shot>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# The exporter needs the app's own views, so it is compiled against every
# source in the app target except its entry point, which it replaces.
sources=$(find "$root/Sources/RoostApp" -name '*.swift' ! -name 'main.swift')

swift build --package-path "$root/Packages/RoostCore" -c release >/dev/null
# SwiftPM nests the build by triple; ask it rather than guessing.
built="$(swift build --package-path "$root/Packages/RoostCore" -c release --show-bin-path)"

# SwiftPM emits no archive for a library nothing links, so its objects are
# handed to the linker directly.
# shellcheck disable=SC2086
swiftc -swift-version 6 -suppress-warnings \
    -I "$built/Modules" \
    -o "$build/export-settings" \
    $sources "$root/scripts/export-settings.swift" "$built"/RoostCore.build/*.o

"$build/export-settings" "$version" \
    "$root/docs/settings.png" "$root/docs/settings.zh-CN.png"
