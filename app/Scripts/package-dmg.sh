#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${FLINT_VERSION:?Set FLINT_VERSION, for example 1.0.0}"
BUILD="${FLINT_BUILD:-$VERSION}"
SIGNING_IDENTITY="${FLINT_SIGNING_IDENTITY:?Set FLINT_SIGNING_IDENTITY to a Developer ID Application identity}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
OUTPUT_DIR="${FLINT_OUTPUT_DIR:-$ROOT_DIR/dist}"
ICON_PATH="$ROOT_DIR/Distribution/Flint.icns"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flint-release.XXXXXX")"
APP_PATH="$STAGING_DIR/Flint.app"
DMG_PATH="$OUTPUT_DIR/Flint-$VERSION.dmg"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ ! -f "$ICON_PATH" ]]; then
    echo "Missing release icon: $ICON_PATH" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" swift build -c release --package-path "$ROOT_DIR"
cp "$ROOT_DIR/.build/release/Flint" "$APP_PATH/Contents/MacOS/Flint"
cp "$ICON_PATH" "$APP_PATH/Contents/Resources/Flint.icns"
ln -s /Applications "$STAGING_DIR/Applications"
sed \
    -e "s/__FLINT_VERSION__/$VERSION/g" \
    -e "s/__FLINT_BUILD__/$BUILD/g" \
    "$ROOT_DIR/Distribution/Info.plist" > "$APP_PATH/Contents/Info.plist"

codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$ROOT_DIR/Distribution/Flint.entitlements" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$DMG_PATH" "$DMG_PATH.sha256"
hdiutil create \
    -volname Flint \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")

echo "Created $DMG_PATH"
echo "Next: FLINT_DMG_PATH=$DMG_PATH FLINT_NOTARY_PROFILE=<profile> $ROOT_DIR/Scripts/notarize-dmg.sh"
