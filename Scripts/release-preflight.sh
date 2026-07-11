#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
SIGNING_IDENTITY="${FLINT_SIGNING_IDENTITY:-}"
ICON_PATH="$ROOT_DIR/Distribution/Flint.icns"

if [[ ! -f "$ICON_PATH" ]]; then
    echo "FAIL: release icon is missing at $ICON_PATH" >&2
    exit 1
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*\"\(Developer ID Application:.*\)\"/\1/p' | head -n 1)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "FAIL: no Developer ID Application signing identity is available in the login keychain." >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
    echo "FAIL: signing identity was not found: $SIGNING_IDENTITY" >&2
    exit 1
fi

for command in codesign hdiutil otool shasum xcrun; do
    if ! command -v "$command" >/dev/null; then
        echo "FAIL: required command is unavailable: $command" >&2
        exit 1
    fi
done

MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" swift build -c release --package-path "$ROOT_DIR"
MINIMUM_OS="$(otool -l "$ROOT_DIR/.build/release/Flint" | awk '/LC_BUILD_VERSION/ { found=1; next } found && /minos/ { print $2; exit }')"
if [[ "$MINIMUM_OS" != "$DEPLOYMENT_TARGET" ]]; then
    echo "FAIL: release binary targets macOS $MINIMUM_OS, expected $DEPLOYMENT_TARGET" >&2
    exit 1
fi

echo "PASS: release preflight succeeded"
echo "Signing identity: $SIGNING_IDENTITY"
echo "Minimum macOS version: $MINIMUM_OS"
