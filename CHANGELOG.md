# Changelog

## Unreleased

- New `"disableFourFingerGestures": true`: the trackpad's four-finger gestures are off while calmtile runs and come back
  on quit or pause (backup in `~/.config/calmtile/gestures-backup.plist`). Off by default.
- New `"backdrop": true`: a theme-coloured layer under the tiled windows (only the area they cover, only while the
  desktop has some), so the rounded window corners macOS draws show a dark seam instead of the wallpaper. Off by default.
- A video in fullscreen stays in fullscreen: browsers and video players are now in `fullscreenApps` by default.
  calmtile took them out of it like any other window, so YouTube left fullscreen right after entering it.
- The focus border flashes only when a focus key (`⌘←` and so on) moves the focus, not on every focus change;
  `"borderFlash": 0` keeps it on all the time.
- New windows reach their tile right away: Terminal 33 ms after its first frame instead of 600 ms, Chrome before it
  is visible, a starting app about 150 ms after its first frame instead of about 800 ms.
- New action `new-window <App>`, the default on `⇧⌘Return`: a new window on this workspace on every press.
- `open` and `new-window` no longer switch to the desktop of an app's other windows.
- An app too busy to answer no longer makes a new window float for good.
- Two windows whose minimum sizes fit neither side by side nor stacked no longer jump between the two for good: a
  minimum learned on one axis is kept when the other is learned. They stay side by side without overlapping, the
  one asking for the largest share of the desktop on the left, the other past the right screen edge. With three or
  more the largest floats, not whichever was measured last, and tiles again as soon as two windows are left.
- A window that does not grow to its tile is no longer written to on every tick.
- The launcher shows applications in the system language ("Kalender" on a German Mac, not "Calendar"), read from
  each app's own bundle. The file name still finds them, launch counts carry over, and a system helper with the
  same translated name as the real app ("Kontakte" for `PeopleViewService`) is no longer listed. `open` and
  `new-window` bindings and `scratchpadApp` keep the names they use today.

## 0.1.0 – 2026-11-06

The first version. Built and tested on macOS 26 with one display; see [docs/development.md](docs/development.md)
for what has been verified live and what has not (`⌘⌥N` only through the action, not the key combination).

**Layout**
- Hyprland's dwindle layout on whole-point tiles, gaps, a focused-window border that flashes on focus changes,
  eight themes.
- Minimum sizes an app insists on are learned and given room (in desktops mode splits are flipped to make them
  fit before a window floats; self-test only so far); windows that cannot be resized tile at their own
  size for the apps in `tileFixedApps` (the iOS Simulator) and float otherwise.
- A window that snaps to its own grid (Terminal) leaves no strip of desktop beside its neighbours: they take
  what it does not use of its tile.
- Floating, calmtile's own fullscreen, a scratchpad with a drop-down terminal.
- A new window beside a fixed-size one opens where there is room; a window that has to float after all goes
  back to the frame its app gave it.

**Workspaces**
- Nine workspaces on `⌘1…9`, `⌘⌥1…9` to send a window there, back-and-forth, a second display for 6–9.
- Parked mode (default): inactive workspaces are parked in a corner, spread out while Mission Control is open.
- Desktops mode (`useSpaces`): workspaces are real macOS desktops with stable numbers, switched through the
  Dock's shortcut, created on demand and optionally removed when left empty (`removeEmptyDesktops`).

**Keys, mouse, launcher**
- Omarchy-style `⌃⌥`/`⌘` keys and the AeroSpace `⌥` keys; every binding configurable on physical key positions.
- Modifier drag to move, swap and resize; title-bar drag swaps tiles.
- A launcher for windows, apps, actions and themes, and an applications-only launcher on `⌘Space`, ranked by
  word starts and how often an app is started. An opt-in switch restricts the system Spotlight to applications.

**Window rules**
- A window that enters macOS's own fullscreen is taken out of it and tiled (`exitFullscreen`, exceptions in
  `fullscreenApps`). Measured once on a test desktop; `exitFullscreen: false` and `fullscreenApps` not yet.
- Only standard windows are managed; dialogs, sheets, popovers, panels without window buttons and system
  prompts float or are left alone. Per-app `floatApps`, `floatTitles`, `ignoreApps`, `passthroughApps`
  (a password manager by default).

**Robustness**
- The key tap runs on its own thread and the windows are listed on another, every Accessibility call gives up
  after 150 ms, an app that does not answer is backed off, late keys are dropped instead of running late.
- A closed window's room goes to its neighbour within about 0.1 s; a hidden app's windows give up their tiles
  in desktops mode.
- Config problems (unknown keys, wrong types, unknown key combinations or actions) are reported at launch and
  on reload, in an alert and the log.
- Idle tick p95 under 20 ms, under 50 ms while windows open, close and desktops switch (profile line in the
  debug log).

**Tooling**
- A logo and app icon, drawn from one list of tiles by `scripts/make-icon.swift`.
- `scripts/build.sh` (self-test, build, sign), CI on macOS 15, test aids (`--post-key`, `--post-drag`,
  `--dump-windows`, the command file, `scripts/matrix.sh`), `scripts/check-docs.sh` (links, anchors, config keys and switches against the docs),
  `scripts/screenshots.sh` (stops rather than capture a window it did not stage), a manual, first steps and the desktops notes.
