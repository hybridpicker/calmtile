#!/bin/bash
# Behaviour matrix for the running instance: every action once, through the command file, on the workspace
# shown now. Needs calmtile started with CALMTILE_DEBUG=1 (the command file is read in debug mode only).
# Prints, per action, the log lines it produced that point at a problem, and at the end the window count and
# the counts of slow/busy/late/dropped lines. Reads only the log (no titles are ever written there).
#
#   scripts/matrix.sh            run on the current workspace: use an empty test desktop and open the windows
#                                you want in the matrix (0, 1, 2, 5) yourself. It opens no window itself, except
#                                that "scratchpad" on an empty scratchpad opens scratchpadApp (a Terminal) by
#                                design: with no window on the workspace it leaves two of them in the scratchpad.
set -euo pipefail
LOG="$HOME/Library/Logs/calmtile.log"
CMD="$HOME/.config/calmtile/command"
pgrep -f calmtile.app/Contents/MacOS >/dev/null || { echo "calmtile is not running"; exit 1; }

ACTIONS=(
  "focus left" "focus right" "focus up" "focus down"
  "swap left" "swap right" "resize left" "resize right" "resize-grow" "resize-shrink"
  "toggle-split" "toggle-float" "toggle-float" "toggle-fullscreen" "toggle-fullscreen"
  "move-to-scratchpad" "scratchpad" "scratchpad" "scratchpad" "move-to-scratchpad" "toggle-float"
  "back-and-forth" "back-and-forth" "reload"
)
# The scratchpad steps send the focused window there, show, hide and show it, and put it back as a tile, so the
# workspace ends as it began. Not in the list: "pause" (the command file is not read while paused, so it would stay paused), "theme-next" and
# "theme" (they write ~/.config/calmtile/theme), "open", "close", "workspace", "move-to-workspace" (they change
# which windows exist and where; test those by hand).

start=$(wc -l < "$LOG")
run() {
  local before
  before=$(wc -l < "$LOG")
  echo "$1" > "$CMD"
  sleep 1.2
  local out
  out=$(tail -n +"$((before + 1))" "$LOG" | grep -E "not an action|busy|slow:|dropped|late|error|failed" || true)
  if [ -n "$out" ]; then echo "[$1]"; echo "$out" | sed 's/^/    /'; else echo "[$1] ok"; fi
}
for a in "${ACTIONS[@]}"; do run "$a"; done

part=$(mktemp)
trap 'rm -f "$part"' EXIT
tail -n +"$((start + 1))" "$LOG" > "$part"
echo "-- windows seen (last): $(grep -o 'windows seen=[0-9]*' "$part" | tail -1)"
for p in "slow:" "busy" "late" "dropped" "did not answer"; do
  echo "-- $p: $(grep -c -- "$p" "$part" || true)"
done
