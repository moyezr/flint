#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${FLINT_VERSION:?Set FLINT_VERSION, for example 0.1.0-beta.11}"
REPOSITORY="${FLINT_GITHUB_REPOSITORY:-moyezr/flint}"
TAG="${FLINT_RELEASE_TAG:-v$VERSION}"
DMG_PATH="${FLINT_DMG_PATH:-$ROOT_DIR/dist/Flint-$VERSION.dmg}"
CHECKSUM_PATH="${FLINT_CHECKSUM_PATH:-$DMG_PATH.sha256}"

for command in gh shasum; do
    if ! command -v "$command" >/dev/null; then
        echo "Required command is unavailable: $command" >&2
        exit 1
    fi
done

if [[ ! -f "$DMG_PATH" || ! -f "$CHECKSUM_PATH" ]]; then
    echo "Missing release artifact or checksum." >&2
    echo "Expected: $DMG_PATH" >&2
    echo "Expected: $CHECKSUM_PATH" >&2
    exit 1
fi

gh auth status >/dev/null

(
    cd "$(dirname "$DMG_PATH")"
    shasum -a 256 -c "$(basename "$CHECKSUM_PATH")"
)

if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG_PATH" "$CHECKSUM_PATH" \
        --clobber \
        --repo "$REPOSITORY"
else
    release_arguments=(
        release create "$TAG"
        "$DMG_PATH"
        "$CHECKSUM_PATH"
        --generate-notes
        --repo "$REPOSITORY"
        --target main
        --title "Flint $VERSION"
    )
    if [[ "$VERSION" == *-* ]]; then
        release_arguments+=(--prerelease)
    fi
    gh "${release_arguments[@]}"
fi

echo "Published Flint $VERSION to GitHub Releases."
