#!/bin/bash
# Stage three neutral windows on the current workspace, capture the tiling and the launcher, clean up.
#
#   scripts/screenshots.sh            writes docs/screenshots/tiling.png and launcher.png
#
# Run it from Terminal on an empty workspace with calmtile running. macOS asks for Screen Recording for
# Terminal the first time; allow it and run the script again. Nothing personal ends up in the pictures:
# TextEdit shows sample text, Terminal a calendar behind a plain prompt, Preview a system wallpaper.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/screenshots
APP=~/Applications/calmtile.app
mkdir -p "$OUT"
[ -d "$APP" ] || { echo "install calmtile first (scripts/build.sh install)"; exit 1; }
pgrep -x calmtile >/dev/null || { echo "start calmtile first"; exit 1; }

WALL=$(ls /System/Library/Desktop\ Pictures/*.heic 2>/dev/null | head -1)
SAMPLE=$(mktemp -d)/calmtile.txt
cat > "$SAMPLE" <<'TXT'
calmtile

A new window splits the focused one along its longer side.
Closing a window gives its space to the sibling.

  Cmd+1..9        switch workspace
  Cmd+Alt+1..9    send the window there
  Cmd+Space       applications
  Ctrl+Alt+Space  windows, apps, actions, themes
TXT

osascript -e 'tell application "Terminal" to do script "PROMPT=\"%% \"; clear; cal; echo; echo \"tiled by the dwindle layout\""' >/dev/null
sleep 1
open -a TextEdit "$SAMPLE"
sleep 1
[ -n "$WALL" ] && open -a Preview "$WALL"
sleep 2.5
screencapture -x "$OUT/tiling.png"

# The applications launcher with a query (bare letters are allowed by --post-key).
open -g -n -a "$APP" --args --post-key cmd-space
sleep 0.8
for k in t e r; do open -g -n -a "$APP" --args --post-key "$k"; sleep 0.15; done
sleep 0.6
screencapture -x "$OUT/launcher.png"
open -g -n -a "$APP" --args --post-key escape
sleep 0.5

# Clean up what was opened.
osascript -e 'tell application "TextEdit" to close (every document whose name is "calmtile.txt") saving no' >/dev/null 2>&1 || true
[ -n "$WALL" ] && osascript -e 'tell application "Preview" to close (every document whose path is "'"$WALL"'")' >/dev/null 2>&1 || true
osascript -e 'tell application "Terminal" to close (every window whose name contains "cal")' >/dev/null 2>&1 || true

for f in tiling launcher; do
  sips -Z 1440 "$OUT/$f.png" >/dev/null   # Retina capture down to 1440 px wide
done
echo "wrote $OUT/tiling.png and $OUT/launcher.png"
