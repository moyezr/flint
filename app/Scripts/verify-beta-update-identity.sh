#!/bin/bash
set -euo pipefail

OLD_DMG="${1:?Usage: verify-beta-update-identity.sh <old.dmg> <new.dmg>}"
NEW_DMG="${2:?Usage: verify-beta-update-identity.sh <old.dmg> <new.dmg>}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flint-beta-identity.XXXXXX")"
OLD_MOUNT="$WORK_DIR/old"
NEW_MOUNT="$WORK_DIR/new"

cleanup() {
    hdiutil detach "$OLD_MOUNT" -quiet >/dev/null 2>&1 || true
    hdiutil detach "$NEW_MOUNT" -quiet >/dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

for path in "$OLD_DMG" "$NEW_DMG"; do
    if [[ ! -f "$path" ]]; then
        echo "DMG does not exist: $path" >&2
        exit 1
    fi
done

mkdir -p "$OLD_MOUNT" "$NEW_MOUNT"
hdiutil attach -readonly -nobrowse -mountpoint "$OLD_MOUNT" "$OLD_DMG" >/dev/null
hdiutil attach -readonly -nobrowse -mountpoint "$NEW_MOUNT" "$NEW_DMG" >/dev/null

OLD_APP="$OLD_MOUNT/Flint.app"
NEW_APP="$NEW_MOUNT/Flint.app"
codesign --verify --deep --strict --verbose=2 "$OLD_APP"
codesign --verify --deep --strict --verbose=2 "$NEW_APP"

OLD_REQUIREMENT="$(codesign -d -r- "$OLD_APP" 2>&1 | sed -n -e 's/^designated => //p' -e 's/^# designated => //p')"
NEW_REQUIREMENT="$(codesign -d -r- "$NEW_APP" 2>&1 | sed -n -e 's/^designated => //p' -e 's/^# designated => //p')"

if [[ -z "$OLD_REQUIREMENT" || -z "$NEW_REQUIREMENT" ]]; then
    echo "Could not read both designated requirements." >&2
    exit 1
fi
if [[ "$OLD_REQUIREMENT" == *cdhash* || "$NEW_REQUIREMENT" == *cdhash* ]]; then
    echo "At least one build still has a version-specific ad-hoc designated requirement." >&2
    exit 1
fi
if [[ "$OLD_REQUIREMENT" != "$NEW_REQUIREMENT" ]]; then
    echo "The two builds do not share the same designated requirement." >&2
    echo "Old: $OLD_REQUIREMENT" >&2
    echo "New: $NEW_REQUIREMENT" >&2
    exit 1
fi

codesign --verify --deep --strict "-R=$OLD_REQUIREMENT" "$NEW_APP"
codesign --verify --deep --strict "-R=$NEW_REQUIREMENT" "$OLD_APP"

echo "Compatible Flint beta update identity verified."
echo "Designated requirement: $OLD_REQUIREMENT"
