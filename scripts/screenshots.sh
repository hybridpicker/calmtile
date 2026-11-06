#!/bin/bash
# Stage three everyday windows on the current workspace, capture the tiling and the launcher, clean up.
#
#   scripts/screenshots.sh            writes docs/screenshots/tiling.png and launcher.png
#
# Run it from Terminal on an empty workspace with calmtile running, with Word closed. macOS asks for Screen
# Recording for Terminal the first time; allow it and run the script again. What the pictures show is staged:
# Word holds a sample document, Chrome the public project page in a throwaway profile (no account, bookmarks or
# history of yours, and it needs the network), Terminal the project's log behind a plain prompt.
# The capture is the whole screen, so the script hides every other app (a chat, your own Chrome, a mail client)
# and minimises your Terminal windows while it works, then brings them back. Word can still show the account
# it is signed in to, so look at the pictures before committing them.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/screenshots
APP=~/Applications/calmtile.app
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PAGE="https://github.com/hybridpicker/calmtile#readme"
mkdir -p "$OUT"
[ -d "$APP" ] || { echo "install calmtile first (scripts/build.sh install)"; exit 1; }
pgrep -x calmtile >/dev/null || { echo "start calmtile first"; exit 1; }
[ -x "$CHROME" ] || { echo "Google Chrome is not installed"; exit 1; }
[ -d "/Applications/Microsoft Word.app" ] || { echo "Microsoft Word is not installed"; exit 1; }

# Word's start window lists recent files, and only a Word started here opens straight into the sample.
if pgrep -x "Microsoft Word" >/dev/null; then
  echo "Microsoft Word is running; quit it and run the script again." >&2
  exit 1
fi

# --- keep everything else out of the pictures -----------------------------------------------------------
# Hiding goes through NSRunningApplication, which needs no extra permission. Minimising Terminal windows
# asks once for permission to control Terminal. Your Chrome has the same name as the staged one, so apps are
# told apart by process id.
HIDDEN=""        # process ids of the apps this script hid, restored on exit
TERMWINS=""      # ids of the Terminal windows this script minimised, restored on exit
CHROME_PID=0     # the staged Chrome
STAGED_TERM=""   # the staged Terminal window
STAGED_WORD=0    # 1 once this script has started Word
TMP=$(mktemp -d)

hide_others() {
  local out
  out=$(osascript -l JavaScript -e 'ObjC.import("AppKit");
var keep = ["calmtile", "Terminal", "Microsoft Word"];
var apps = $.NSWorkspace.sharedWorkspace.runningApplications;
var out = [];
for (var i = 0; i < apps.count; i++) {
  var a = apps.objectAtIndex(i);
  if (a.activationPolicy == 0 && !a.hidden && a.processIdentifier != '"$CHROME_PID"' &&
      keep.indexOf(ObjC.unwrap(a.localizedName)) < 0) {
    out.push(a.processIdentifier);
    a.hide();
  }
}
out.join(" ")' 2>/dev/null || true)
  [ -n "$out" ] && HIDDEN="$HIDDEN $out"
  return 0
}

# Asks the window server, so controlling Word takes no permission. Reading titles comes with Screen Recording.
word_shows_sample() {
  osascript -l JavaScript -e 'ObjC.import("CoreGraphics");
var wins = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(0, 0)));
wins.some(function (w) {
  return w.kCGWindowOwnerName == "Microsoft Word" && w.kCGWindowLayer == 0 && w.kCGWindowIsOnscreen &&
         (w.kCGWindowName || "").indexOf("calmtile") >= 0;
})' 2>/dev/null | grep -q true
}

# A new window splits the focused one, so the next window needs Chrome in front.
activate_chrome() {
  osascript -l JavaScript -e 'ObjC.import("AppKit");
var apps = $.NSWorkspace.sharedWorkspace.runningApplications;
for (var i = 0; i < apps.count; i++) {
  var a = apps.objectAtIndex(i);
  if (a.processIdentifier == '"$CHROME_PID"') a.activateWithOptions($.NSApplicationActivateIgnoringOtherApps);
}' >/dev/null 2>&1 || true
}

finish() {
  set +e   # one failed step must not leave the rest hidden or open
  # Close what was opened.
  if [ "$STAGED_WORD" = 1 ]; then
    osascript -l JavaScript -e 'ObjC.import("AppKit");
var apps = $.NSWorkspace.sharedWorkspace.runningApplications;
for (var i = 0; i < apps.count; i++) {
  var a = apps.objectAtIndex(i);
  if (ObjC.unwrap(a.bundleIdentifier) == "com.microsoft.Word") a.terminate;
}' </dev/null >/dev/null 2>&1
    for _ in 1 2 3 4 5; do
      pgrep -x "Microsoft Word" >/dev/null || break
      sleep 1
    done
    pkill -x "Microsoft Word"   # it was started here and only ever held the sample
  fi
  if [ -n "$STAGED_TERM" ]; then
    osascript -e "tell application \"Terminal\" to close (every window whose id is $STAGED_TERM) saving no" </dev/null >/dev/null 2>&1
  fi
  if [ "$CHROME_PID" != 0 ]; then
    kill "$CHROME_PID" 2>/dev/null
    sleep 1
  fi
  rm -rf "$TMP"
  # Bring back what was put aside.
  for id in $TERMWINS; do
    osascript -e "tell application \"Terminal\" to set miniaturized of (every window whose id is ${id%,}) to false" </dev/null >/dev/null 2>&1
  done
  osascript -l JavaScript -e 'ObjC.import("AppKit");
var want = " '"$HIDDEN"' ";
var apps = $.NSWorkspace.sharedWorkspace.runningApplications;
for (var i = 0; i < apps.count; i++) {
  var a = apps.objectAtIndex(i);
  if (want.indexOf(" " + a.processIdentifier + " ") >= 0) a.unhide();
}' </dev/null >/dev/null 2>&1
  return 0
}
trap finish EXIT

minimise_terminals() {
  osascript -e "tell application \"Terminal\"
  repeat with w in windows
    if id of w is not ${STAGED_TERM:-0} then set miniaturized of w to true
  end repeat
end tell" >/dev/null 2>&1 || true
}

# Prints the owners of the windows on screen that were not staged; empty when there are none. A window left
# over also takes a tile, so this has to hold before each staged window opens, not only for the capture.
# $1 is the number of Terminal windows that are staged.
foreign_windows() {
  osascript -l JavaScript -e 'ObjC.import("CoreGraphics");
var wins = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(0, 0)));
var terminals = 0, out = [];
wins.forEach(function (w) {
  if (w.kCGWindowLayer != 0 || !w.kCGWindowIsOnscreen || w.kCGWindowBounds.Height <= 100) return;
  var o = w.kCGWindowOwnerName;
  if ((w.kCGWindowName || "").indexOf("'"$(id -un)"'") >= 0) { out.push(o + " (its title shows your user name)"); return; }
  if (o == "Terminal" && ++terminals <= '"$1"') return;
  if (o == "Microsoft Word" || o == "calmtile" || w.kCGWindowOwnerPID == '"$CHROME_PID"') return;
  out.push(o);
});
out.join(", ")' 2>/dev/null || echo "unknown (asking the window server failed)"
}

# Your own windows show your user name, your files and your apps, so the script stops rather than capture them.
check_screen() {
  local left=""
  for _ in 1 2 3 4 5; do
    minimise_terminals
    hide_others
    sleep 0.8
    left=$(foreign_windows "$1")
    [ -z "$left" ] && return 0
  done
  echo "still on screen and not staged: $left; close it and run the script again, nothing captured" >&2
  exit 1
}

# Minimise the Terminal windows that are open now (this one included); they come back at the end.
if pgrep -x Terminal >/dev/null; then
  TERMWINS=$(osascript -e 'tell application "Terminal" to get id of every window whose miniaturized is false' 2>/dev/null || true)
fi
check_screen 0

cat > "$TMP/sample.html" <<'HTML'
<html><body>
<h1>calmtile</h1>
<p>A new window splits the focused one along its longer side. Closing a window gives its space to the sibling.</p>
<h2>Keys</h2>
<p>Cmd+1..9: switch workspace</p>
<p>Cmd+Alt+1..9: send the window there</p>
<p>Cmd+Space: applications</p>
<p>Ctrl+Alt+Space: windows, apps, actions, themes</p>
<h2>Windows</h2>
<p>Dialogs, sheets, popovers and system prompts are left alone. Everything else finds its place by itself, so
there is nothing to drag and nothing to arrange.</p>
</body></html>
HTML
textutil -convert docx -output "$TMP/calmtile.docx" "$TMP/sample.html"

# The first window gets the left half, the second the upper right, the third the lower right.
STAGED_WORD=1
open -a "Microsoft Word" "$TMP/calmtile.docx" --args -AppleLanguages '(en)'
for _ in $(seq 1 60); do
  word_shows_sample && break
  sleep 1
done
word_shows_sample || { echo "Word did not show the sample within 60 s" >&2; exit 1; }
sleep 2
check_screen 0

# A page in another language than the browser would bring up the translation bubble.
mkdir -p "$TMP/chrome/Default"
cat > "$TMP/chrome/Default/Preferences" <<'JSON'
{ "translate": { "enabled": false }, "intl": { "accept_languages": "en-US,en" } }
JSON
"$CHROME" --user-data-dir="$TMP/chrome" --no-first-run --no-default-browser-check --disable-sync \
  --disable-search-engine-choice-screen "$PAGE" >/dev/null 2>&1 &
CHROME_PID=$!
sleep 10   # the page has to be drawn, not only requested
check_screen 0
activate_chrome
sleep 0.5

# The log is written once the window has its tile, because a resize can leave the text blank.
cat > "$TMP/log.sh" <<LOG
clear
git --no-pager -C '$PWD' log --color=always --format='%C(yellow)%h%Creset %<(70,trunc)%s' -n 16
LOG
STAGED_TERM=$(osascript -e 'tell application "Terminal"
  set t to do script "PROMPT=\"%% \"; cd '"'$PWD'"'; clear"   -- the title names the folder, in the home folder your user
  set custom title of t to "calmtile"
  return id of front window
end tell')
sleep 2.5
check_screen 1
osascript -e "tell application \"Terminal\" to do script \"sh '$TMP/log.sh'\" in window id $STAGED_TERM" >/dev/null
sleep 1.5
screencapture -x "$OUT/tiling.png"

# The applications launcher with a query (bare letters are allowed by --post-key). The list comes from the apps
# you have installed, so the query is narrow enough to show only a few.
open -g -n -a "$APP" --args --post-key cmd-space
sleep 0.8
for k in t e r m i; do open -g -n -a "$APP" --args --post-key "$k"; sleep 0.15; done
sleep 0.6
check_screen 1
screencapture -x "$OUT/launcher.png"
open -g -n -a "$APP" --args --post-key escape
sleep 0.5

for f in tiling launcher; do
  sips -Z 1440 "$OUT/$f.png" >/dev/null   # Retina capture down to 1440 px wide
done
echo "wrote $OUT/tiling.png and $OUT/launcher.png"
