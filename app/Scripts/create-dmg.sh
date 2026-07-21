#!/bin/bash
set -euo pipefail

SOURCE_DIR="${1:?Usage: create-dmg.sh <source-directory> <output.dmg> [volume-name]}"
OUTPUT_PATH="${2:?Usage: create-dmg.sh <source-directory> <output.dmg> [volume-name]}"
VOLUME_NAME="${3:-Flint}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flint-dmg.XXXXXX")"
READ_WRITE_DMG="$WORK_DIR/Flint-read-write.dmg"
DEVICE_PATH=""

cleanup() {
    if [[ -n "$DEVICE_PATH" ]]; then
        hdiutil detach "$DEVICE_PATH" -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "DMG source directory does not exist: $SOURCE_DIR" >&2
    exit 1
fi

for command in ditto hdiutil osascript; do
    if ! command -v "$command" >/dev/null; then
        echo "Required command is unavailable: $command" >&2
        exit 1
    fi
done

SOURCE_KILOBYTES="$(du -sk "$SOURCE_DIR" | awk '{print $1}')"
IMAGE_MEGABYTES="$((SOURCE_KILOBYTES / 1024 + 24))"

hdiutil create \
    -size "${IMAGE_MEGABYTES}m" \
    -fs HFS+ \
    -volname "$VOLUME_NAME" \
    "$READ_WRITE_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$READ_WRITE_DMG")"
DEVICE_PATH="$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' '$2 ~ /Apple_HFS/ { gsub(/[[:space:]]/, "", $1); print $1; exit }')"
MOUNT_PATH="$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' '$NF ~ /^\/Volumes\// { print $NF; exit }')"

if [[ -z "$DEVICE_PATH" || -z "$MOUNT_PATH" || ! -d "$MOUNT_PATH" ]]; then
    echo "Could not mount the writable DMG." >&2
    exit 1
fi

ditto "$SOURCE_DIR" "$MOUNT_PATH"

HAS_README=false
if [[ -f "$MOUNT_PATH/READ ME FIRST.txt" ]]; then
    HAS_README=true
fi
MOUNT_NAME="$(basename "$MOUNT_PATH")"

osascript - "$MOUNT_NAME" "$HAS_README" <<'APPLESCRIPT'
on run arguments
    set mountedVolumeName to item 1 of arguments
    set hasReadme to item 2 of arguments is "true"

    tell application "Finder"
        tell disk mountedVolumeName
            open
            delay 1
            set installerWindow to container window
            set current view of installerWindow to icon view
            set toolbar visible of installerWindow to false
            set statusbar visible of installerWindow to false
            set pathbar visible of installerWindow to false
            set sidebar width of installerWindow to 0
            set bounds of installerWindow to {200, 150, 840, 570}

            set installerView to icon view options of installerWindow
            set arrangement of installerView to not arranged
            set icon size of installerView to 112
            set text size of installerView to 14
            set shows item info of installerView to false
            set shows icon preview of installerView to true

            set position of item "Flint.app" to {170, 170}
            set position of item "Applications" to {470, 170}
            if hasReadme then
                set position of item "READ ME FIRST.txt" to {320, 330}
            end if

            update without registering applications
            delay 2
            close installerWindow
        end tell
    end tell
end run
APPLESCRIPT

sync
hdiutil detach "$DEVICE_PATH" -quiet
DEVICE_PATH=""

rm -f "$OUTPUT_PATH"
hdiutil convert "$READ_WRITE_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_PATH" >/dev/null

echo "Created compact DMG: $OUTPUT_PATH"
