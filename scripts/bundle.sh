#!/usr/bin/env bash
# Builds Illuminate.app from the Swift package and signs it.
#
#   scripts/bundle.sh                 # release build, ad-hoc signed, into ./build
#   SIGN_IDENTITY="Developer ID Application: …" scripts/bundle.sh
#
# Ad-hoc signing is enough to run locally and for SMAppService. For distribution,
# sign with a Developer ID identity (hardened runtime is enabled then) and notarize.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
OUT_DIR="${OUT_DIR:-build}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="$OUT_DIR/Illuminate.app"

swift build -c "$CONFIG" --product Illuminate
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Illuminate" "$APP/Contents/MacOS/Illuminate"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# codesign rejects bundles carrying provenance/FinderInfo xattrs ("resource fork … detritus").
xattr -cr "$APP"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP"
