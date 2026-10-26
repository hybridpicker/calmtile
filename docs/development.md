# Development

## Build

```bash
scripts/build.sh           # self-test, then build/calmtile.app
scripts/build.sh install   # additionally copy to ~/Applications
```

Plain `swiftc` from the Xcode Command Line Tools; no Xcode project, no dependencies. The two SwiftPM
targets in `Package.swift` are compiled as one module. The app is signed with the first "Apple Development"
identity found (`CALMTILE_SIGN_ID` overrides), because macOS keeps the Accessibility grant across rebuilds
only for a stable signature; without one it falls back to an ad-hoc signature and the grant has to be given
again after each build.

## Structure

- `Sources/CalmCore` – dwindle tree (`DwindleTree.swift`), workspaces, focus and layout decisions
  (`Engine.swift`), fuzzy matching for the launcher, themes, the Spotlight category list. No AppKit.
- `Sources/calmcore-selftest` – the checks `scripts/build.sh` runs before every build (layout, workspaces,
  focus, scratchpad, minimum sizes, monitors, launcher matching).
- `Sources/calmtile` – the app: `Windows.swift` (Accessibility), `Hotkeys.swift` (event tap on its own
  thread), `Controller.swift` (the loop that reconciles windows, applies the plan, handles actions, menu bar,
  mouse; the window listing of each tick runs on a serial queue of its own and the rest on the main thread), `Spaces.swift` (real desktops: window server calls, Mission Control through the Dock's
  accessibility tree, system shortcut state), `Launcher.swift`, `Config.swift`, `Border.swift`,
  `Spotlight.swift`, `LoginItem.swift`, `main.swift` (one-shot commands and test aids).

## Log and debugging

`~/Library/Logs/calmtile.log` holds window counts, actions, permission state and desktop re-homings; window
titles are never written. `CALMTILE_DEBUG=1` in the environment (for example
`launchctl setenv CALMTILE_DEBUG 1` before `open -a calmtile`, and `launchctl unsetenv` afterwards) adds every
placement with frames, what the Accessibility list shows after a desktop switch, and the "created" path of
new windows.

With `CALMTILE_DEBUG=1` (or `CALMTILE_PROFILE=1` for the profile alone) every 20 full ticks write one
`profile:` line: the workspace shown, how long the 20 ticks took (5 s at the active rate of 250 ms, 20 s
once the loop has slowed to 1 s for lack of anything happening), main-thread time per tick (p50, p95, max),
time per phase (`observe` registers notifications, `list(thread)` is how long the listing thread took to
ask the apps for their windows, which no longer counts as main-thread time, `reconcile` matches them against
the window server, `focus`, `float`, `place`, `border`), Accessibility and window
server calls per tick, the apps that took longest to list, notifications by kind and app, and how long
hotkeys waited for the main thread (`late` when the key tap had to decide without it). Numbers and bundle
ids only.

`calmtile --print-config` prints the effective config; `--restore-spotlight`, `--install-login` and
`--uninstall-login` are the one-shot commands described in the README.

## Test aids

All of these must run through `open`, so macOS applies the app's Accessibility grant; the bare binary is
not trusted and gets nothing.

- `open -g -n -a ~/Applications/calmtile.app --args --post-key cmd-space` synthesizes a key press for the
  running instance. `-g` keeps the helper from taking the foreground, which would close the launcher it
  just opened. Bare keys are allowed (`--post-key escape`).
- `open -g -n -a ~/Applications/calmtile.app --stdout out.txt --args --dump-windows` prints one line per
  window of every regular app: role, subrole, resizable, buttons, size and position, never the title.
  One-shot helpers see a placeholder instead of windows for Electron apps, whose accessibility tree is
  only built after `AXManualAccessibility` is switched on; the running instance has done that long before.
- Real desktops: `--remove-desktop N` removes desktop N through Mission Control (undo for a desktop created
  by `⌘N`); `--dump-dock [depth]` prints the Dock's accessibility tree while Mission Control is open
  (identifiers, no window titles); `--probe-switch N` switches to desktop N with the direct window server
  call and back, printing every 50 ms which desktop is active and which windows Accessibility lists;
  `--probe-hotkey-switch N [--delay s] [--restore-after s]` does it through the Dock shortcut and prints the
  shown Spaces.
- **Do not judge desktop switching through helper launches.** Launching any helper app from a shell
  (`open -n -a …`, a scratch app) makes macOS re-activate the app that owns that shell about a second
  later, and with real desktops that switches back to its desktop: every switch then looks undone. With
  `CALMTILE_DEBUG=1` the running instance executes an action written to `~/.config/calmtile/command`
  (`echo "workspace 2" > ~/.config/calmtile/command`) on its next tick, with no helper involved; watch the
  window server from a plain command-line tool.
- Mission Control cannot be driven and apps expose no Accessibility windows while the screen is locked.

## Screenshots

`scripts/screenshots.sh` stages three neutral windows on the current workspace (TextEdit with sample text,
Terminal with a calendar, Preview with a system wallpaper), captures `docs/screenshots/tiling.png`, opens the
`⌘Space` launcher with a query and captures `docs/screenshots/launcher.png`, then closes what it opened.
macOS asks for Screen Recording for the app that runs it the first time (Terminal, or the app that hosts
your shell) and once for permission to control Terminal.

The capture is the whole screen, so the script keeps everything else out of it. It hides every other app
(`NSRunningApplication.hide`, no extra permission), minimises the open Terminal windows, restores both on
exit, and stops without staging anything if TextEdit or Preview already have windows open. The staged
Terminal window is titled `calmtile` and closed by its id. Look at both pictures before committing them:
no chat, mail, browser, user name or file name belongs in them.

## What has been verified live

On macOS 26.5, one 1440 × 900 display, menu bar and Dock hidden:

- Start and quit, `⌘Space` and `⌘1…9` interception (by synthesized keys and window dumps).
- Parked mode: Mission Control spreading and re-parking.
- Real desktops: `⌘1→2→3→1` through the Dock shortcut switches desktops; after each switch the window
  server shows exactly one Space and keeps it; every window stays on its own desktop at its size, no window
  is re-homed, no focus pulls macOS back. Creating a missing desktop with `⌘4`/`⌘5`. Terminal's 724 px
  snapped width is trimmed to 716 px beside a 720 px neighbour.
- Window inspection of Calendar, VLC, Terminal, Dashlane, Notes, Mail, Finder, Safari, Preview, Teams, Zoom
  and VS Code.
- Spotlight preference write and restore (checked with `defaults`).
- The `⌘Space` launcher appears with Spotlight staying closed; the app activates itself from the event tap,
  which macOS 14+ may grant late, so it asks twice.

On macOS 26.5.2 (same display, desktops mode, a heavily loaded machine: load average 30-110, swap nearly
full), from the debug log and the profile line, with actions sent through the command file:

- A Terminal opened beside another window and closed again, 13 times in a row: each Terminal window is
  placed once (716 px in its 720 px tile, then left alone), and the neighbour grows back to the full width
  after the close.
- Desktop switches 2→1→2 with that in between: window counts as expected, no window re-homed.
- An app stopped with `kill -STOP` for 10 s (TextEdit, two windows): ticks stay under 160 ms, the windows
  keep their tiles, nothing is logged as slow; it resumes normally after `kill -CONT`.
- The tick in numbers (see the profile line): idle p95 under 20 ms at one tick per second, under 50 ms
  while windows open, close and desktops switch; no `slow:` or `main thread busy` line.
- `⌘Space` panel (from the command file): built and ordered front in under 20 ms after the first time.

Not verified yet: title-bar drag swap; Chrome with several windows and Picture-in-Picture; `⌘⌥N` with real
desktops; whether a new window is visibly placed before its first frame (by eye; the log shows it placed
0.3-0.45 s after the command, usually by the tick rather than the creation notification); Zoom meetings;
Xcode; a second display (self-tests only); whether Spotlight visibly honours the category list; parked mode
since the changes of October 2026 (self-tests only).

## Privacy notes

Window titles are read for the launcher and the title rules only and are never logged. The key tap only
compares key codes and modifiers against the bindings; nothing is stored. While a password manager or any
app in `passthroughApps` is frontmost, no key is intercepted. Secure keyboard entry blocks the tap entirely.
