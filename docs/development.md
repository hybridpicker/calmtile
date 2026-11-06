# Development

## Build

```bash
scripts/build.sh           # self-test, then build/calmtile.app
scripts/build.sh install   # additionally copy to ~/Applications
CALMTILE_STRICT=1 scripts/build.sh   # warnings are errors, as in CI
```

Plain `swiftc` from the Xcode Command Line Tools; no Xcode project, no dependencies. The build targets macOS
14 whatever the build machine runs. The two SwiftPM
targets in `Package.swift` are compiled as one module. The app is signed with the first "Apple Development"
identity found (`CALMTILE_SIGN_ID` overrides), because macOS keeps the Accessibility grant across rebuilds
only for a stable signature; without one it falls back to an ad-hoc signature and the grant has to be given
again after each build.

## Structure

- `Sources/CalmCore` – dwindle tree (`DwindleTree.swift`), workspaces, focus and layout decisions
  (`Engine.swift`), fuzzy matching and the result order for the launcher (`Fuzzy.swift`), themes, the
  Spotlight category list. No AppKit.
- `Sources/calmcore-selftest` – the checks `scripts/build.sh` runs before every build (layout, workspaces,
  focus, scratchpad, minimum sizes, monitors, launcher matching).
- `assets` – the logo and the app icon, both written by `scripts/make-icon.swift` from one list of tiles.
  `scripts/build.sh` copies the icon into the app.
- `Sources/calmtile` – the app: `Windows.swift` (Accessibility: the listing with its per-app memory of
  the last answers, timeouts and back-off, window frames from the window server), `Hotkeys.swift` (event tap on its own
  thread), `Controller.swift` (the loop that reconciles windows, applies the plan, handles actions, menu bar,
  mouse; the window listing of each tick runs on a serial queue of its own and the rest on the main thread), `Spaces.swift` (real desktops: window server calls, Mission Control through the Dock's
  accessibility tree, system shortcut state), `Launcher.swift`, `Config.swift`, `Border.swift`,
  `Spotlight.swift`, `LoginItem.swift`, `Log.swift` (the log file), `Profile.swift` (the profile line),
  `main.swift` (one-shot commands and test aids).

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
- `open -g -n -a ~/Applications/calmtile.app --args --post-drag x0 y0 x1 y1` drags with the left button from one
  point to another (global coordinates), for the title-bar drag. Mouse events posted by a tool started from a
  shell are dropped by macOS, because the shell's app has no Accessibility grant.
- `scripts/matrix.sh` runs every action once through the command file on the workspace shown and reports the
  log lines that point at a problem (numbers and bundle ids only). Use a test desktop.
- **Do not judge desktop switching through helper launches.** Launching any helper app from a shell
  (`open -n -a …`, a scratch app) makes macOS re-activate the app that owns that shell about a second
  later, and with real desktops that switches back to its desktop: every switch then looks undone. With
  `CALMTILE_DEBUG=1` the running instance executes an action written to `~/.config/calmtile/command`
  (`echo "workspace 2" > ~/.config/calmtile/command`) on its next tick, with no helper involved; watch the
  window server from a plain command-line tool.
- Mission Control cannot be driven and apps expose no Accessibility windows while the screen is locked.

## Screenshots

`scripts/screenshots.sh` stages three windows on the current workspace (Word with a sample document, Chrome
with the public project page, Terminal with the project's log), captures `docs/screenshots/tiling.png`, opens
the `⌘Space` launcher with a query and captures `docs/screenshots/launcher.png`, then closes what it opened.
It needs the network for the page. macOS asks for Screen Recording for the app that runs it the first time
(Terminal, or the app that hosts your shell) and once for permission to control Terminal.

The capture is the whole screen, so the script keeps everything else out of it. It hides every other app
(`NSRunningApplication.hide`, no extra permission), your own Chrome included, minimises the open Terminal
windows, restores both on exit, and stops without staging anything if Word is running, because Word's start
window lists recent files. The staged Chrome runs in a throwaway profile in a temporary folder, so it has no
account, bookmarks or history; the staged Terminal window is titled `calmtile` and closed by its id. The script
asks the window server before each staged window and each capture, and stops if a window it did not stage is
still on screen, since a prompt shows the user and machine name and a leftover window takes a tile, or if a
window's title contains your user name. Word can
still show the account it is signed in to, and the launcher lists the apps you have installed. Look at both
pictures before committing them: no chat, mail, account, user name, private app or file name belongs in them.

## What has been verified live

On macOS 26.5, one 1440 × 900 display, menu bar and Dock hidden:

- Start and quit, `⌘Space` and `⌘1…9` interception (by synthesized keys and window dumps).
- Parked mode: Mission Control spreading and re-parking.
- Real desktops: `⌘1→2→3→1` through the Dock shortcut switches desktops; after each switch the window
  server shows exactly one Space and keeps it; every window stays on its own desktop at its size, no window
  is re-homed, no focus pulls macOS back. Creating a missing desktop with `⌘4`/`⌘5`. Terminal's 724 px
  snapped width is trimmed to 716 px, and its neighbours take what it leaves: in a screenshot of Word, Chrome
  and Terminal the windows meet with no strip and no overlap, Terminal reaching both screen edges.
- Window inspection of Calendar, VLC, Terminal, Dashlane, Notes, Mail, Finder, Safari, Preview, Teams, Zoom
  and VS Code.
- Spotlight preference write and restore (checked with `defaults`).
- The `⌘Space` launcher appears with Spotlight staying closed; the app activates itself from the event tap,
  which macOS 14+ may grant late, so it asks twice.

On macOS 26.5.2 (same display, desktops mode, a heavily loaded machine: load average 30-110, swap nearly
full), from the debug log and the profile line, with actions sent through the command file:

- A Terminal opened beside another window and closed again, 13 times in a row: each Terminal window is
  placed once (716 px in its 720 px tile, then left alone), and the neighbour grows back to the full width
  after the close: 0.105-0.113 s after it on 4 Nov 2026 (0.5 s before a closing window was recognised by its
  element).
- Desktop switches 2→1→2 with that in between: window counts as expected, no window re-homed.
- An app stopped with `kill -STOP` for 10 s (TextEdit, two windows): ticks stay under 160 ms, the windows
  keep their tiles, nothing is logged as slow; it resumes normally after `kill -CONT`.
- The tick in numbers (see the profile line): idle p95 under 20 ms at one tick per second, under 50 ms
  while windows open, close and desktops switch; no `slow:` or `main thread busy` line.
- `⌘Space` panel (from the command file): built and ordered front in under 20 ms after the first time.

On 4 Nov 2026 (same setup, a test desktop, actions through the command file):

- `tileFixedApps`: an iOS Simulator window (410 × 880, not resizable) beside a Terminal sits in a tile of its
  own size at the right edge, the Terminal takes the rest; window server and Accessibility agree on both
  frames, and nothing is placed again afterwards.
- A hidden app (`NSRunningApplication.hide`, as `⌘H`): its window loses its tile and the neighbour takes the
  full width within a tick; shown again, both tiles come back.
- A new window beside a focused fixed-size one (the Simulator) opens next to it at full height; TextEdit's
  open panel at launch floats.
- A desktop switch away and back 300 ms apart (`workspace 2`, `workspace 1`): 0.2 s later the window server
  shows exactly one Space, no `late` or `dropped` key, nothing placed during the animation.
- TextEdit stopped with `kill -STOP` for 10 s, two windows: main-thread ticks at most 20 ms, tiles unchanged.
- `removeEmptyDesktops`: leaving an empty desktop removes exactly that one, also with a full-screen app's Space
  in the Spaces bar (it used to remove the desktop left of it); a desktop holding only a minimized window
  stays. Creating a desktop clicks the right button of the bar.
- Title-bar drag (`--post-drag`): the window follows the pointer and swaps with the tile it is dropped on.
- The `⌘Space` panel opened from the command file is the key window after 17-62 ms; picking an app writes only
  its name to `launcher-usage.json`.
- The listing thread: no `slow:` or `main thread busy` line all day with the current builds; `list(thread)` in
  the profile line, not part of the tick time.
- A config with a misspelt key or a wrong type: reported at launch in the log (`config: …`). The alert uses the
  same call as on reload; nobody looked at it on screen in this run.
- `scripts/matrix.sh` with 0, 1, 2 and 5 windows: no problem line.
- A new window is drawn at its own size before it is placed: measured from the window server every 10 ms,
  a new Terminal shows for 0.24-0.5 s at its own frame (including macOS's 0.23 s opening animation) and is
  then placed by the tick; the creation notification comes while Terminal is still too busy to answer.

On 5 Nov 2026 (test desktop, TextEdit, native fullscreen entered with `⌃⌘F`): with `exitFullscreen` on, the window's fullscreen Space appeared and was gone again about a second later, the log says `fullscreen left: com.apple.TextEdit`, and the view was back on the test desktop. The exception list (`fullscreenApps`) and `exitFullscreen: false` were not exercised.

On 5 Nov 2026 (second run, test desktop, config `{}` so parked mode, actions through the command file):

- first-steps steps 3 and 4: two `open Terminal` give two tiles with gaps; an empty workspace hides the others (parked at the bottom-right corner), a Terminal opened there fills it; back-and-forth and `move-to-workspace` do what the text says; a third window splits the focused one.
- Mission Control spreads the windows of all workspaces while it is open; after it closes the workspace shows its tiles again. Closing it re-activates the last window, so the workspace of that window is shown (parked mode follows activation). Re-parking of a window on another workspace was not looked at.
- Four windows (two Terminals, TextEdit, Dictionary) on one desktop with `useSpaces`: all tiled, none overlapping. Their minimum sizes were small, so the flipped-splits path was not exercised live.

On 5 Nov 2026 (third run, test desktop 5, `move-to-workspace 4` from the command file, staged TextEdit window): the window went to desktop 4 in about half a second (`moved window to desktop 4`), was tiled beside the window already there, and the test desktop and TextEdit were removed again afterwards (the Spaces list shows four). Only the action was sent, not the key combination.

Not verified yet:

- `⌘⌥N` pressed as a real key combination (the action through the command file works, see above), `exitFullscreen: false` and the `fullscreenApps` exception.
- docs/first-steps.md steps 5 to 9 (focus keys, launcher, config edit, desktops, undo) on a fresh config; steps 1 to 4 were followed (see above).
- `⌘Space` pressed on the real keyboard (the panel was only opened through the command file).
- Chrome with several windows, two profiles, Picture-in-Picture and DevTools; Zoom meetings and screen
  sharing; Xcode's secondary windows (Organizer, Devices, inspectors); Claude Desktop's popups; Finder's
  info, copy and connect dialogs and Quick Look; window dumps of Mail, Safari, Notes, Calendar, Preview, VLC,
  Dashlane, Teams and VS Code since October.
- A trackpad swipe between desktops: whether windows are written their frame while the swipe animates (one
  case in the log, not reproducible without a real gesture).
- A second display (self-tests only).
- Whether Spotlight visibly honours the category list of `spotlightAppsOnly`.
- The screenshots (`scripts/screenshots.sh` needs Screen Recording for the app that runs it).

## Privacy notes

Window titles are read for the launcher and the title rules only and are never logged. The key tap only
compares key codes and modifiers against the bindings; nothing is stored. While a password manager or any
app in `passthroughApps` is frontmost, no key is intercepted. Secure keyboard entry blocks the tap entirely.
