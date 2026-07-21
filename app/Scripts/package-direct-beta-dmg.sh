#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${FLINT_VERSION:?Set FLINT_VERSION, for example 0.1.0-beta.1}"
BUILD="${FLINT_BUILD:-$VERSION}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
OUTPUT_DIR="${FLINT_OUTPUT_DIR:-$ROOT_DIR/dist}"
ICON_PATH="$ROOT_DIR/Distribution/Flint.icns"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flint-direct-beta.XXXXXX")"
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

for command in swift codesign hdiutil osascript shasum; do
    if ! command -v "$command" >/dev/null; then
        echo "Required command is unavailable: $command" >&2
        exit 1
    fi
done

mkdir -p "$OUTPUT_DIR" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" swift build -c release --package-path "$ROOT_DIR"
cp "$ROOT_DIR/.build/release/Flint" "$APP_PATH/Contents/MacOS/Flint"
cp "$ICON_PATH" "$APP_PATH/Contents/Resources/Flint.icns"
cp "$ROOT_DIR/.build/checkouts/argmax-oss-swift/LICENSE" "$APP_PATH/Contents/Resources/ArgmaxOSS-LICENSE.txt"
cp "$ROOT_DIR/.build/checkouts/argmax-oss-swift/NOTICES" "$APP_PATH/Contents/Resources/ArgmaxOSS-NOTICES.txt"
cp "$ROOT_DIR/.build/checkouts/swift-argument-parser/LICENSE.txt" "$APP_PATH/Contents/Resources/SwiftArgumentParser-LICENSE.txt"
cp "$ROOT_DIR/Distribution/READ ME FIRST.txt" "$STAGING_DIR/READ ME FIRST.txt"
ln -s /Applications "$STAGING_DIR/Applications"
sed \
    -e "s/__FLINT_VERSION__/$VERSION/g" \
    -e "s/__FLINT_BUILD__/$BUILD/g" \
    "$ROOT_DIR/Distribution/Info.plist" > "$APP_PATH/Contents/Info.plist"

# This is an anonymous ad-hoc signature, not Developer ID signing. It gives
# the bundle a stable executable seal but does not satisfy Gatekeeper.
codesign \
    --force \
    --entitlements "$ROOT_DIR/Distribution/Flint.entitlements" \
    --sign - \
    "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$DMG_PATH" "$DMG_PATH.sha256"
"$ROOT_DIR/Scripts/create-dmg.sh" "$STAGING_DIR" "$DMG_PATH" "Flint"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")

echo "Created direct-beta DMG: $DMG_PATH"
echo "Created checksum: $DMG_PATH.sha256"
echo "This artifact is not Developer ID signed or notarized. Test Gatekeeper approval on a clean macOS user before publishing it."
