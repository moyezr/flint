#!/bin/bash
set -euo pipefail

DMG_PATH="${FLINT_DMG_PATH:?Set FLINT_DMG_PATH to the signed DMG}"
NOTARY_PROFILE="${FLINT_NOTARY_PROFILE:?Set FLINT_NOTARY_PROFILE to a notarytool keychain profile}"

if [[ ! -f "$DMG_PATH" ]]; then
    echo "DMG not found: $DMG_PATH" >&2
    exit 1
fi

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"

echo "Notarization and Gatekeeper validation passed: $DMG_PATH"
