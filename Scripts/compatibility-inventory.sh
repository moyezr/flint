#!/bin/bash
set -euo pipefail

target_apps=(
    "TextEdit|/System/Applications/TextEdit.app"
    "Notes|/System/Applications/Notes.app"
    "Safari|/Applications/Safari.app"
    "Google Chrome|/Applications/Google Chrome.app"
    "Arc|/Applications/Arc.app"
    "Firefox|/Applications/Firefox.app"
    "Slack|/Applications/Slack.app"
    "Discord|/Applications/Discord.app"
    "Cursor|/Applications/Cursor.app"
    "VS Code|/Applications/Visual Studio Code.app"
    "Xcode|/Applications/Xcode.app"
    "Terminal|/System/Applications/Utilities/Terminal.app"
    "iTerm2|/Applications/iTerm.app"
    "Messages|/System/Applications/Messages.app"
    "Microsoft Word|/Applications/Microsoft Word.app"
)

printf '# Flint Compatibility Inventory\n\n'
printf 'Generated: %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf -- '- macOS: %s\n' "$(sw_vers -productVersion)"
printf -- '- Build: %s\n' "$(sw_vers -buildVersion)"
printf -- '- Hardware: %s\n\n' "$(sysctl -n hw.model)"
printf '| Surface | Installed | Version | Path |\n'
printf '| --- | --- | --- | --- |\n'

for target in "${target_apps[@]}"; do
    IFS='|' read -r name path <<< "$target"
    if [[ -d "$path" ]]; then
        version="$(defaults read "$path/Contents/Info" CFBundleShortVersionString 2>/dev/null || printf 'Unknown')"
        printf '| %s | Yes | %s | `%s` |\n' "$name" "$version" "$path"
    else
        printf '| %s | No | - | `%s` |\n' "$name" "$path"
    fi
done
