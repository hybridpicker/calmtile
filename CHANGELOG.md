# Changelog

## 0.1.0 – unreleased

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
  `fullscreenApps`). Not measured live yet.
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
- `scripts/build.sh` (self-test, build, sign), CI on macOS 15, test aids (`--post-key`, `--post-drag`,
  `--dump-windows`, the command file, `scripts/matrix.sh`), `scripts/check-docs.sh` (links, anchors, config keys and switches against the docs), a manual, first steps and the desktops notes.
