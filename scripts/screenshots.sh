#!/bin/bash
# Stage three neutral windows on the current workspace, capture the tiling and the launcher, clean up.
#
#   scripts/screenshots.sh            writes docs/screenshots/tiling.png and launcher.png
#
# Run it from Terminal on an empty workspace with calmtile running. macOS asks for Screen Recording for
# Terminal the first time; allow it and run the script again. Nothing personal ends up in the pictures:
# TextEdit shows sample text, Terminal a calendar behind a plain prompt, Preview a system wallpaper.
# The capture is the whole screen, so the script hides every other app (a chat, a browser, a mail client)
# and minimises your Terminal windows while it works, then brings them back. It stops if TextEdit or Preview
# already have windows open, because staging would show them.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/screenshots
APP=~/Applications/calmtile.app
mkdir -p "$OUT"
[ -d "$APP" ] || { echo "install calmtile first (scripts/build.sh install)"; exit 1; }
pgrep -x calmtile >/dev/null || { echo "start calmtile first"; exit 1; }

# --- keep everything else out of the pictures -----------------------------------------------------------
# Hiding goes through NSRunningApplication, which needs no extra permission. Minimising Terminal windows
# asks once for permission to control Terminal.
HIDDEN=""        # bundle ids of the apps this script hid, restored on exit
TERMWINS=""      # ids of the Terminal windows this script minimised, restored on exit

hide_others() {
  local out
  out=$(osascript -l JavaScript -e 'ObjC.import("AppKit");
var keep = ["calmtile", "Terminal", "TextEdit", "Preview"];
var apps = $.NSWorkspace.sharedWorkspace.runningApplications;
var out = [];
for (var i = 0; i < apps.count; i++) {
  var a = apps.objectAtIndex(i);
  if (a.activationPolicy == 0 && !a.hidden && keep.indexOf(ObjC.unwrap(a.localizedName)) < 0) {
    out.push(ObjC.unwrap(a.bundleIdentifier));
    a.hide();
  }
}
out.join(" ")' 2>/dev/null || true)
  [ -n "$out" ] && HIDDEN="$HIDDEN $out"
  return 0
}

finish() {
  for id in $TERMWINS; do
    osascript -e "tell application \"Terminal\" to set miniaturized of (every window whose id is ${id%,}) to false" </dev/null >/dev/null 2>&1
  done
  for b in $HIDDEN; do
    osascript -l JavaScript -e "ObjC.import('AppKit'); var r = \$.NSRunningApplication.runningApplicationsWithBundleIdentifier('$b'); if (r.count > 0) r.objectAtIndex(0).unhide();" </dev/null >/dev/null 2>&1
  done
  return 0
}
trap finish EXIT

# TextEdit and Preview are staged below; a window of yours in either would end up in the picture.
for app in TextEdit Preview; do
  if pgrep -x "$app" >/dev/null; then
    n=$(osascript -e "tell application \"$app\" to count windows" 2>/dev/null || echo 0)
    if [ "${n:-0}" != "0" ]; then
      echo "$app has $n open window(s); close them and run the script again." >&2
      exit 1
    fi
  fi
done

# Minimise the Terminal windows that are open now (this one included); they come back at the end.
if pgrep -x Terminal >/dev/null; then
  TERMWINS=$(osascript -e 'tell application "Terminal" to get id of every window whose miniaturized is false' 2>/dev/null || true)
  osascript -e 'tell application "Terminal" to set miniaturized of every window to true' >/dev/null 2>&1 || true
fi
hide_others
sleep 0.5

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

STAGED_TERM=$(osascript -e 'tell application "Terminal"
  set t to do script "PROMPT=\"%% \"; clear; cal; echo; echo \"tiled by the dwindle layout\""
  set custom title of t to "calmtile"
  return id of front window
end tell')
sleep 1
open -a TextEdit "$SAMPLE"
sleep 1
[ -n "$WALL" ] && open -a Preview "$WALL"
sleep 2.5
hide_others; sleep 0.4
screencapture -x "$OUT/tiling.png"

# The applications launcher with a query (bare letters are allowed by --post-key).
open -g -n -a "$APP" --args --post-key cmd-space
sleep 0.8
for k in t e r; do open -g -n -a "$APP" --args --post-key "$k"; sleep 0.15; done
sleep 0.6
hide_others; sleep 0.3
screencapture -x "$OUT/launcher.png"
open -g -n -a "$APP" --args --post-key escape
sleep 0.5

# Clean up what was opened.
osascript -e 'tell application "TextEdit" to close (every document whose name is "calmtile.txt") saving no' >/dev/null 2>&1 || true
[ -n "$WALL" ] && osascript -e 'tell application "Preview" to close (every document whose path is "'"$WALL"'")' >/dev/null 2>&1 || true
[ -n "$STAGED_TERM" ] && osascript -e "tell application \"Terminal\" to close (every window whose id is $STAGED_TERM) saving no" >/dev/null 2>&1 || true

for f in tiling launcher; do
  sips -Z 1440 "$OUT/$f.png" >/dev/null   # Retina capture down to 1440 px wide
done
echo "wrote $OUT/tiling.png and $OUT/launcher.png"
