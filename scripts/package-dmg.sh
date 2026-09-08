#!/usr/bin/env bash
# Builds Roost in Release and packages it as a DMG.
#
# The same script runs locally and in CI, so a release that works on a laptop
# is the one that ships.
set -euo pipefail

version="${1:?usage: scripts/package-dmg.sh <version>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

derived="$root/.release"
staging="$derived/dmg"
dmg="$root/Roost-$version.dmg"

rm -rf "$derived" "$dmg"
xcodegen generate

# Ad-hoc signed: there is no Developer ID here, and an unsigned app cannot be
# notarised anyway. Gatekeeper's first-launch warning is covered in the notes.
xcodebuild -project Roost.xcodeproj -scheme Roost -configuration Release \
    -derivedDataPath "$derived" \
    MARKETING_VERSION="$version" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    build

app="$derived/Build/Products/Release/Roost.app"
test -x "$app/Contents/MacOS/roost-hook" || {
    echo "roost-hook is missing from the bundle; approvals would silently do nothing" >&2
    exit 1
}

mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Roost $version" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null

echo "$dmg"
