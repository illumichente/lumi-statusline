#!/bin/bash
# Installs (or removes with --uninstall) lumi-statusline for Claude Code.
# Copies statusline.sh to ~/.claude/ and sets statusLine in ~/.claude/settings.json.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
DEST="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

if [ "$1" = "--uninstall" ]; then
    if [ -f "$DEST.bak" ]; then mv "$DEST.bak" "$DEST"; echo "restored previous statusline from statusline.sh.bak"
    else rm -f "$DEST"; echo "removed $DEST"; fi
    [ -f "$SETTINGS" ] && jq 'del(.statusLine)' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    rm -f "$HOME/.claude/cache/statusline-usage.json"
    echo "done, restart Claude Code"; exit 0
fi

case "$(uname -s)" in
    Darwin) hint="brew install jq" ;;
    Linux)  hint="sudo apt install jq   # or your distro's package manager" ;;
    MINGW*|MSYS*|CYGWIN*) hint="winget install jqlang.jq   # then reopen Git Bash" ;;
    *) echo "unsupported OS: $(uname -s)"; exit 1 ;;
esac
for dep in jq curl; do command -v "$dep" >/dev/null || { echo "missing $dep ($hint)"; exit 1; }; done

mkdir -p "$HOME/.claude"
[ -f "$DEST" ] && ! cmp -s "$SRC" "$DEST" && cp "$DEST" "$DEST.bak" && echo "backed up existing statusline to statusline.sh.bak"
cp "$SRC" "$DEST" && chmod 755 "$DEST"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq '.statusLine = {type:"command", command:"bash \"$HOME/.claude/statusline.sh\"", refreshInterval:30}' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
echo "installed to $DEST, settings.json updated. Restart Claude Code (or it reloads on its own)."
