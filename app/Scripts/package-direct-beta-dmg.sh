#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${FLINT_VERSION:?Set FLINT_VERSION, for example 0.1.0-beta.1}"
BUILD="${FLINT_BUILD:-$VERSION}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
OUTPUT_DIR="${FLINT_OUTPUT_DIR:-$ROOT_DIR/dist}"
ICON_PATH="$ROOT_DIR/Distribution/Flint.icns"
FONT_SOURCE_DIR="$ROOT_DIR/Sources/Flint/Resources/Fonts"
FONT_LICENSE_SOURCE_DIR="$ROOT_DIR/Sources/Flint/Resources/FontLicenses"
FLINT_LICENSE_PATH="$ROOT_DIR/../LICENSE"
BETA_SIGNING_DIR="${FLINT_BETA_SIGNING_DIR:-$HOME/Library/Application Support/Flint Beta Signing}"
BETA_SIGNING_IDENTITY="${FLINT_BETA_SIGNING_IDENTITY:-Flint Beta Signing}"
BETA_SIGNING_KEYCHAIN="${FLINT_BETA_SIGNING_KEYCHAIN:-$BETA_SIGNING_DIR/FlintBeta.keychain-db}"
BETA_SIGNING_PASSWORD_FILE="${FLINT_BETA_SIGNING_PASSWORD_FILE:-$BETA_SIGNING_DIR/keychain-password}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flint-direct-beta.XXXXXX")"
APP_PATH="$STAGING_DIR/Flint.app"
DMG_PATH="$OUTPUT_DIR/Flint-$VERSION.dmg"
SIGNING_KEYCHAIN_UNLOCKED=false

cleanup() {
    if [[ "$SIGNING_KEYCHAIN_UNLOCKED" == true ]]; then
        security lock-keychain "$BETA_SIGNING_KEYCHAIN" >/dev/null 2>&1 || true
    fi
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

for command in swift codesign hdiutil osascript security shasum; do
    if ! command -v "$command" >/dev/null; then
        echo "Required command is unavailable: $command" >&2
        exit 1
    fi
done

if [[ ! -f "$BETA_SIGNING_KEYCHAIN" || ! -f "$BETA_SIGNING_PASSWORD_FILE" ]]; then
    echo "Missing persistent Flint beta signing identity." >&2
    echo "Run $ROOT_DIR/Scripts/setup-beta-signing-identity.sh before packaging a public beta." >&2
    exit 1
fi
if ! security list-keychains -d user | grep -Fq "\"$BETA_SIGNING_KEYCHAIN\""; then
    echo "The Flint beta signing keychain is not on the user keychain search list." >&2
    echo "Run $ROOT_DIR/Scripts/setup-beta-signing-identity.sh to repair the local signing setup." >&2
    exit 1
fi

BETA_SIGNING_PASSWORD="$(tr -d '\r\n' < "$BETA_SIGNING_PASSWORD_FILE")"
security unlock-keychain -p "$BETA_SIGNING_PASSWORD" "$BETA_SIGNING_KEYCHAIN"
SIGNING_KEYCHAIN_UNLOCKED=true
BETA_SIGNING_IDENTITY_HASH="$(
    security find-identity -v -p codesigning "$BETA_SIGNING_KEYCHAIN" \
        | awk -v identity="\"$BETA_SIGNING_IDENTITY\"" 'index($0, identity) { print $2; exit }'
)"
if [[ -z "$BETA_SIGNING_IDENTITY_HASH" ]]; then
    echo "Signing identity '$BETA_SIGNING_IDENTITY' is unavailable in $BETA_SIGNING_KEYCHAIN." >&2
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

# This persistent private beta identity keeps Flint's designated requirement
# stable across builds. It is not Developer ID signing and does not satisfy
# Gatekeeper or enable notarization.
codesign \
    --force \
    --entitlements "$ROOT_DIR/Distribution/Flint.entitlements" \
    --keychain "$BETA_SIGNING_KEYCHAIN" \
    --sign "$BETA_SIGNING_IDENTITY_HASH" \
    "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

DESIGNATED_REQUIREMENT="$(codesign -d -r- "$APP_PATH" 2>&1 | sed -n -e 's/^designated => //p' -e 's/^# designated => //p')"
if [[ -z "$DESIGNATED_REQUIREMENT" || "$DESIGNATED_REQUIREMENT" == *cdhash* ]]; then
    echo "The packaged app does not have a stable certificate-backed designated requirement." >&2
    exit 1
fi

rm -f "$DMG_PATH" "$DMG_PATH.sha256"
"$ROOT_DIR/Scripts/create-dmg.sh" "$STAGING_DIR" "$DMG_PATH" "Flint"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")

echo "Created direct-beta DMG: $DMG_PATH"
echo "Created checksum: $DMG_PATH.sha256"
echo "Designated requirement: $DESIGNATED_REQUIREMENT"
echo "This artifact is privately signed but is not Developer ID signed or notarized. Test Gatekeeper approval on a clean macOS user before publishing it."
