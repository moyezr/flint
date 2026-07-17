#!/bin/bash
set -euo pipefail

if pgrep -x Flint >/dev/null 2>&1; then
    echo "Quit Flint before resetting onboarding from the command line." >&2
    exit 1
fi

defaults write com.moyezrabbani.Flint hasCompletedOnboarding -bool false
defaults write Flint hasCompletedOnboarding -bool false

echo "Onboarding will start from Welcome the next time Flint launches."
echo "Models, vocabulary, settings, and macOS permission grants were preserved."
