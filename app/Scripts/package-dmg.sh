#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${FLINT_VERSION:?Set FLINT_VERSION, for example 1.0.0}"
BUILD="${FLINT_BUILD:-$VERSION}"
SIGNING_IDENTITY="${FLINT_SIGNING_IDENTITY:?Set FLINT_SIGNING_IDENTITY to a Developer ID Application identity}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
OUTPUT_DIR="${FLINT_OUTPUT_DIR:-$ROOT_DIR/dist}"
ICON_PATH="$ROOT_DIR/Distribution/Flint.icns"
FONT_SOURCE_DIR="$ROOT_DIR/Sources/Flint/Resources/Fonts"
FONT_LICENSE_SOURCE_DIR="$ROOT_DIR/Sources/Flint/Resources/FontLicenses"
FLINT_LICENSE_PATH="$ROOT_DIR/../LICENSE"
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

if [[ ! -d "$FONT_SOURCE_DIR" || ! -d "$FONT_LICENSE_SOURCE_DIR" ]]; then
    echo "Missing bundled Flint font resources." >&2
    exit 1
fi
if [[ ! -f "$FLINT_LICENSE_PATH" ]]; then
    echo "Missing Flint license: $FLINT_LICENSE_PATH" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
mkdir -p "$APP_PATH/Contents/Resources/Fonts" "$APP_PATH/Contents/Resources/FontLicenses"

MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" swift build -c release --package-path "$ROOT_DIR"
cp "$ROOT_DIR/.build/release/Flint" "$APP_PATH/Contents/MacOS/Flint"
cp "$ICON_PATH" "$APP_PATH/Contents/Resources/Flint.icns"
cp "$FONT_SOURCE_DIR"/*.ttf "$APP_PATH/Contents/Resources/Fonts/"
cp "$FONT_LICENSE_SOURCE_DIR"/*.txt "$APP_PATH/Contents/Resources/FontLicenses/"
cp "$FLINT_LICENSE_PATH" "$APP_PATH/Contents/Resources/Flint-LICENSE.txt"
cp "$ROOT_DIR/.build/checkouts/argmax-oss-swift/LICENSE" "$APP_PATH/Contents/Resources/ArgmaxOSS-LICENSE.txt"
cp "$ROOT_DIR/.build/checkouts/argmax-oss-swift/NOTICES" "$APP_PATH/Contents/Resources/ArgmaxOSS-NOTICES.txt"
cp "$ROOT_DIR/.build/checkouts/swift-argument-parser/LICENSE.txt" "$APP_PATH/Contents/Resources/SwiftArgumentParser-LICENSE.txt"
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
"$ROOT_DIR/Scripts/create-dmg.sh" "$STAGING_DIR" "$DMG_PATH" "Flint"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")

echo "Created $DMG_PATH"
echo "Next: FLINT_DMG_PATH=$DMG_PATH FLINT_NOTARY_PROFILE=<profile> $ROOT_DIR/Scripts/notarize-dmg.sh"
