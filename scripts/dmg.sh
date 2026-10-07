#!/usr/bin/env bash
# Builds Illuminate.app and packs it into a drag-to-install disk image:
#
#   scripts/dmg.sh        # -> build/Illuminate-<version>.dmg
#
# The image contains the app and a link to /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="${OUT_DIR:-build}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)"
DMG="$OUT_DIR/Illuminate-$VERSION.dmg"

OUT_DIR="$OUT_DIR" scripts/bundle.sh

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
# ditto keeps the code signature and extended attributes intact.
ditto "$OUT_DIR/Illuminate.app" "$STAGING/Illuminate.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Illuminate" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "Built $DMG"
