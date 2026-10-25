# hyprmac

A small macOS menu bar app that tiles windows like Hyprland's dwindle layout and switches
workspaces with `Cmd+1…9`. Replaces AeroSpace (do not run both).

## Build and run

```bash
scripts/build.sh install      # self-test, build, copy to ~/Applications
open ~/Applications/hyprmac.app
```

First start: allow it under System Settings → Privacy & Security → **Accessibility**
(and **Input Monitoring** if macOS asks), then start it again. The menu bar shows `▦ <workspace>`
(`▦ ⏸` while paused, `🔒` while secure keyboard entry blocks all hotkeys).

## Default keys

| Keys | Action |
|---|---|
| `⌘1…9` | switch workspace |
| `⌘⌥1…9` | send focused window to workspace |
| `⌘←↑↓→`, `⌃⌥←↑↓→` or `⌃⌥H/J/K/L` | focus neighbour (`⌘`-arrows pass through when there is no neighbour) |
| `⌃⌥⇧←↑↓→` | swap with neighbour |
| `⌃⌥⌘←↑↓→` | move the nearest divider |
| `⌃⌥F` / `⌃⌥T` / `⌃⌥S` | fullscreen / float / flip split |
| `⌃⌥W` | close window |
| `⌃⌥Tab` / `⌥Tab` | previous workspace |
| `⌥←↑↓→`, `⌥H/K` / `⌥⇧←↑↓→` | focus / swap neighbour (AeroSpace keys; `⌥`-arrows pass through when there is no neighbour) |
| `⌥⇧Tab` | move the current workspace to the next display |
| `⌥-` / `⌥=` | shrink / grow the focused window |
| `⌥J` / `⌥W` / `⌥F` / `⌥V` | flip split / close / fullscreen / float (AeroSpace keys) |
| `⌘Return` / `⌃⌥Return` | open a new Terminal window |
| `⇧⌘Return` | open Google Chrome |
| `⌃⌥Q` / `⌃⌥⇧Q` | show/hide the scratchpad / send the focused window there |
| `⌘Space` | own Spotlight: applications only (replaces system Spotlight while hyprmac runs) |
| `⌃⌥Space` | launcher: search windows, apps, actions and themes |
| `⌃⌥⇧Space` | next theme |
| `⌃⌥R` / `⌃⌥P` | reload config / pause tiling |

## Mouse

Hold `⌘⌥` (`"mouseModifier"` in the config, `""` turns it off):

- **left drag** moves the window. A tiled window follows the pointer and, when dropped on another
  tile, swaps places with it; a floating window stays where you drop it.
- **right drag** resizes. For tiled windows the divider follows the pointer; floating windows grow
  from their top-left corner.

Option-letter combos are avoided on purpose: on a German keyboard `⌥L` types `@`.

## Scratchpad

`⌃⌥⇧Q` sends the focused window to the scratchpad: it disappears and belongs to no workspace.
`⌃⌥Q` pops the latest one up as a floating window in the middle of the screen (and hides it
again). With an empty scratchpad `⌃⌥Q` opens `"scratchpadApp"` (default Terminal) and captures
its window, which makes a drop-down terminal. `⌃⌥⇧Q` on a shown scratchpad window puts it
back on the current workspace. The menu bar lists scratchpad windows too.

## Launcher and themes

`⌃⌥Space` opens a search field: type to filter open windows (jump there), installed apps and
hyprmac actions (workspaces, float, themes …); `↑↓`/`Tab` select, `Return` runs, `Esc` closes.

Themes: catppuccin, tokyo-night, gruvbox, nord, rose-pine, everforest, kanagawa,
catppuccin-latte. They colour the focused-window border and the launcher. Pick one in the
launcher (`Theme: …`) or cycle with `⌃⌥⇧Space`; the choice is kept in `~/.config/hyprmac/theme`.
`"theme"` in the config sets the default, `"borderColor": "#rrggbb"` overrides the border colour.

## Layout rules

- A new window splits the focused one along its longer side (dwindle). Closing gives the space
  to its sibling.
- Workspaces 1–5 live on the main display, 6–9 on a second display (if none, on the main one).
- Inactive workspaces are parked at the bottom-right corner of the screen (1 px visible).
- Only `AXStandardWindow` windows are managed. Dialogs, sheets, floating panels, popovers, Picture-in-Picture,
  the Finder desktop and system dialogs are not standard windows and are never tiled, parked or moved.
- Standard windows that cannot be resized float; the apps in `floatApps` float.
- Standard windows with no resize and no close/minimize button (transient popups) and the apps in
  `ignoreApps` (system alert helpers) are not touched at all.
- `floatTitles` (`{"bundle id": ["word", …]}`): standard windows whose title contains a word float (VLC
  playlist/inspector/controller, Chrome DevTools by default). Checked until it matches, once per window, so a
  manual `⌃⌥T` back to tiled sticks. Titles are only compared in memory, never logged.
  Finder info/copy/connect dialogs are not resizable and float on their own.
- Dashlane is in `passthroughApps` by default: no hotkey is intercepted while it is frontmost.

### Key conflicts with apps

Workspace keys win everywhere, as in Hyprland and the AeroSpace setup: hyprmac takes every bound key out of
the event stream before the focused app sees it, so `⌘1…9` switches workspace even in Chrome (tab 1…9) and
Terminal (window 1…9); the apps' own shortcuts need no change. Use `⌃Tab` / `⌃⇧Tab` or `⌘⌥←/→` for Chrome
tabs, `⌘\`` for Terminal windows. To give an app its keys back completely, add its bundle id to
`passthroughApps` (`com.google.Chrome`, `com.apple.Terminal`); that disables all hyprmac hotkeys while it is
frontmost.

The key tap runs on its own thread: an app that stops answering Accessibility calls can delay a workspace
switch, but the key is still swallowed and never reaches the app (the log then says `main thread busy`;
`⌘`-arrows pass through in that case, since the app may own them).

When a hotkey "does nothing" anyway, one of these is the reason:

- **Secure keyboard entry** is on: a password field, a password manager or Terminal's "Secure Keyboard Entry"
  menu item. macOS then delivers keys to no hotkey tool at all. The menu bar shows `▦ 2 🔒`, the menu names
  the app holding it, and the log says `secure keyboard entry on`; hotkeys return as soon as it ends.
- Another hotkey tool started after hyprmac grabs the same key (AeroSpace, Karabiner, Raycast …): later taps
  see the key first. Run only one.
- With `"useSpaces": true`, the desktop is being created (see below); the switch follows within a second.

## Config

`~/.config/hyprmac/config.json` is optional; everything missing falls back to the defaults.
`hyprmac --print-config` (binary inside the .app) prints the effective config.

```json
{
  "gap": 4,
  "outerGap": 6,
  "mainWorkspaces": 5,
  "useSpaces": false,
  "minTileWidth": 420,
  "minTileHeight": 280,
  "spotlightAppsOnly": false,
  "floatApps": ["com.apple.calculator"],
  "floatTitles": { "org.videolan.vlc": ["Playlist"] },
  "ignoreApps": ["com.apple.SecurityAgent"],
  "passthroughApps": ["com.apple.Terminal"],
  "bindings": { "cmd-alt-return": "open Safari", "ctrl-alt-p": "" }
}
```

`passthroughApps`: no hotkey is intercepted while one of these is frontmost (e.g. apps where
`⌘1…9` must keep its own meaning). A binding set to `""` removes the default.
Actions: `scratchpad`, `move-to-scratchpad`, `launcher`, `app-launcher`, `theme <name>`, `theme-next`, `workspace N`, `move-to-workspace N`, `focus|swap|resize <left|right|up|down>`,
`resize-grow`, `resize-shrink`, `toggle-float`, `toggle-fullscreen`, `toggle-split`, `close`, `back-and-forth`, `move-workspace-to-monitor`, `reload`,
`pause`, `open <App name>`.

## Start at login

Off by default. The menu item "Start at login" (or `hyprmac --install-login` / `--uninstall-login`)
writes/removes `~/Library/LaunchAgents/local.hyprmac.plist`, which opens `~/Applications/hyprmac.app`.

## Mission Control

All workspaces live on one macOS Space; inactive ones are parked in a corner. While Mission Control is open
(four-finger swipe up, `⌃↑`) hyprmac moves every window to its layout position, so macOS shows a proper
overview instead of a pile in the corner. When it closes, windows are parked again and the workspace of the
window you picked becomes current. Measured: windows spread within ~0.1 s of opening, parked again after
closing; how smooth the macOS animation looks was not observed. Real macOS Spaces per workspace are not used
(there is no public API to move windows between Spaces).

## Real desktops (`"useSpaces": true`)

Opt-in. Workspace N is a macOS desktop (Space) of the display: `⌘N` switches desktops, windows stay where
macOS puts them, nothing is parked in a corner and Mission Control shows a clean desktop per workspace.

- **Numbers stay with their desktops.** macOS moves the most recently used desktops to the front whenever
  Mission Control opens ("Automatically rearrange Spaces based on most recent use", on by default), so "the
  Nth desktop" is a moving target and `⌘2` would land somewhere else after every swipe up. hyprmac gives a
  desktop the lowest free number when it first sees it (Dock order at the first start) and remembers it in
  `~/.config/hyprmac/desktops.json`; the menu bar shows that number. Mission Control's own order and its
  "Desktop N" labels may differ. With the setting off, the Dock's order is used as it is (a desktop dragged
  elsewhere in Mission Control then takes its new position's number), like the system's `⌃N` shortcuts.
- **A missing workspace is created when you go there** (Hyprland semantics): `⌘N` opens Mission Control for
  about a second, presses its "add desktop" button and clicks the new desktop, which gets number N whatever
  its position (`⌘5` with desktops 1–3 creates only 5). macOS has no API for this short of disabling SIP; the
  Dock's Spaces bar is driven through Accessibility, as yabai does. Verified live on one display; with two
  displays the Spaces bar of the display holding the active desktop is picked by position (not tested).
  Desktops are never removed automatically; `--remove-desktop N` does it by hand.

- **Switching goes through the Dock.** Setting the display's current Space directly (the private call any process
  may make) does only half the job on macOS 26: the new desktop becomes current, but the one just left stays shown
  (the window server then lists two "current" Spaces) and its windows keep being drawn over the new desktop, which
  looked like "the Claude window stays visible on every desktop" and like windows overlapping. Hiding a Space is
  honoured for the Dock alone. So `⌘N` presses the system shortcut "Switch to Desktop <position>" (`⌃<digit>`) for
  the Dock. That shortcut is usually off in System Settings; hyprmac switches it on in the window server for the
  0.4 s of the synthesized press and off again (nothing is written to the preferences, your own `⌃<digit>` keeps its
  meaning). The position is looked up in the Dock's current order at every press, so the automatic rearranging does
  not matter. Verified live 2026-10-25 (window server checked for 5 s after each switch: one shown Space, no return).
  Beyond nine desktops the direct call is used.
- Tiling works per desktop; trackpad swipes and Mission Control are followed (the active desktop becomes the
  current workspace, a window dragged to another desktop changes workspace).
- Which desktop a window is on is read from the window server, never from its presence in the Accessibility
  window list: that list still shows the desktop just left for about 0.3 s after a switch (seen in the debug log).
  Taking those windows as "here" used to tile them into the new workspace, resize them on their own desktop and,
  when one of them was focused, pull macOS straight back to it. Right after a switch, a window of the new desktop
  that Accessibility has not listed yet keeps its tile; a window that is on the desktop but not drawn (minimized,
  its app hidden, ordered out) loses it. The window server's own report wobbles while the Dock animates a switch,
  so a window is re-homed only when two ticks agree and a single Space is shown (a wrong re-homing is what made a
  window keep half of a desktop it had to itself: its supposed neighbour was on another desktop).
- A new window is tiled from the "window created" notification, with the element the notification carries, instead
  of on the next tick: the frame is set while the window is still appearing, so it no longer shows up at the app's
  own size first and then jumps into place (that cannot be avoided entirely, since the app draws its first frame
  itself; apps that restore their last frame open at their tile anyway).
- Windows always tile on their desktop, however small the tiles get (Hyprland): hyprmac cannot move windows
  between Spaces (the private call has no effect on macOS 26.5, verified), so `minTileWidth`/`minTileHeight` only
  apply without `useSpaces`. Only a window whose own minimum size cannot sit beside its neighbours floats.
- `⌘⌥N` (send window to desktop N) drags the window's title bar while pressing the system shortcut `⌃<position>`,
  enabled for that moment the same way. This path is not tested live.
- Only normal desktops of the display holding the active desktop count; full-screen app Spaces are skipped and
  workspaces 6–9 do not move to a second display in this mode.
- Verified live (2026-10-24/25, window-server check after each key): `⌘1→2→3→1` switches desktops and every
  window stays on its own desktop at its size; no window is re-homed, no focus pulls macOS back; Terminal's 724 px
  snapped width is trimmed to 716 px beside a 720 px neighbour. Not yet seen live: the immediate placement of a new
  window and a window growing back after its neighbour closes (the retry rule below was changed for it).

## Own Spotlight: applications only (`⌘Space`)

`⌘Space` opens hyprmac's launcher restricted to applications (installed, with running ones just launching/
activating). hyprmac sees the key before Spotlight, so Spotlight itself no longer opens while hyprmac runs and
nothing in the system settings is touched. Remove it with `"bindings": {"cmd-space": ""}`; `app-launcher` is the
action name. `⌃⌥Space` stays the full launcher (windows, apps, actions, themes).

## Spotlight: applications only (system setting, off by default)

While hyprmac runs, `⌘Space` Spotlight lists only applications (no documents, mail, folders …).
This **changes a system setting** (`orderedItems` in `com.apple.Spotlight`, the same list as System
Settings → Spotlight → Search Results), so hyprmac handles it carefully:

- On start the current list (or "key not set") is saved to `~/.config/hyprmac/spotlight-backup.plist`,
  every category except `APPLICATIONS` is switched off, and the Spotlight UI process is restarted.
- It is **reset to the original on quit** (menu, `SIGTERM`/`SIGINT`/`SIGHUP`), on **pause**, and when
  `"spotlightAppsOnly": false` is set and reloaded. A backup that already exists is never overwritten, so after a
  crash the next start (or `hyprmac --restore-spotlight`) still restores the true original.
- `"spotlightAppsOnly": true` enables it (default `false`, because the own `⌘Space` launcher above does the job without touching the system); the menu item "Spotlight: applications only"
  toggles it for the current run.
- Not verified visually on macOS 26.5: the preference write and restore were checked with `defaults`; whether
  Spotlight honours the key was not observed (no screen access in the dev session). If categories still show,
  restore with `hyprmac --restore-spotlight` and set `"spotlightAppsOnly": false`.

## Development aids

- Test aid: `open -g -n -a ~/Applications/hyprmac.app --args --post-key cmd-space` synthesizes a key press for the running
  instance (it must be launched through `open` so macOS applies the app's Accessibility grant; the bare binary
  is not trusted and the key goes nowhere). `-g` keeps the helper from taking the foreground, which would close the
  launcher it just opened. Bare keys are allowed here (`--post-key escape`).
- Desktops mode: `open -g -n -W -a ~/Applications/hyprmac.app --stdout out.txt --args --probe-switch 2` switches to
  desktop 2 directly (the half-way call) and back, printing every 50 ms which desktop is active and which windows
  Accessibility lists (bundle ids); `--probe-hotkey-switch 2 [--delay s] [--restore-after s]` does it through the Dock
  shortcut and prints the shown Spaces. One-shot helpers see a placeholder instead of windows for Electron apps,
  whose accessibility tree is only built after `AXManualAccessibility` is switched on.
- **Do not judge desktop switching through helper launches.** Launching any helper app from a shell (`open -n -a
  ...`, a scratch app) makes macOS re-activate the app that owns that shell about a second later, and with real
  desktops that switches back to its desktop: every switch then looks undone. With `HYPRMAC_DEBUG=1` the running
  instance executes an action written to `~/.config/hyprmac/command` (`echo "workspace 2" > ~/.config/hyprmac/command`)
  on its next tick, with no helper involved; watch the window server from a plain command-line tool.
- Desktops mode: `open -n -W -a ~/Applications/hyprmac.app --stdout out.txt --args --remove-desktop 4` removes
  desktop 4 through Mission Control (undo for a desktop created by `⌘4`); `--dump-dock [depth]` prints the
  Dock's accessibility tree while Mission Control is open (identifiers, no window titles).
- Inspect real windows (no titles are printed):
  `open -n -a ~/Applications/hyprmac.app --stdout out.txt --args --dump-windows`.
- `hyprmac --print-config` prints the effective config; `--restore-spotlight`, `--install-login`,
  `--uninstall-login` are the one-shot commands described above. `HYPRMAC_DEBUG=1` (environment) logs
  placements to `~/Library/Logs/hyprmac.log`; window titles are never logged.

## Structure

- `Sources/HyprCore` – dwindle tree, workspaces, focus; no AppKit, self-tested (`hyprcore-selftest`).
- `Sources/hyprmac` – Accessibility windows, key tap, config, menu bar, launcher, Spotlight switch, login item.

## Known limits

- No overlap by design: hyprmac learns the minimum size an app insists on and gives that window the room
  (neighbours shrink). A tile is never split below 420×280 px (`minTileWidth`/`minTileHeight`, 0 turns it off). If a window cannot fit on the workspace without
  overlapping (e.g. Calendar ≥ 908 px plus another app ≥ 600 px on a 1440 px screen), it opens on / moves to the
  next workspace with room and hyprmac switches there; `⌘1…9` goes back. Only when no workspace has room it floats.
- Windows are moved by the app after they open (no compositor), so a short flicker remains possible; the frame is
  set from the creation notification to keep it short.
- A window that is smaller than its tile, or sits elsewhere, is placed again on every tick until it matches (a set
  call may have timed out while the app was busy). Only a window that came out larger than its tile (the app's
  minimum size) is left alone after a few tries.
- Apps that snap their size to a grid (Terminal: character cells) come out a few pixels larger than their tile
  and would overlap the neighbour; hyprmac then asks once more for a size reduced by the overshoot, so the snapped
  result stays inside the tile.
- A tiled window dragged by its title bar swaps with the tile it is dropped on, or snaps back to its own
  tile (detected by polling every 0.25 s, so a very quick tiny drag may be missed). Resizing a tiled
  window by its edge snaps back; use the mouse modifier + right drag to move dividers.
- macOS native fullscreen windows are left alone (they live on their own Space and are invisible to hyprmac).
- Verified live (by synthesized keys and window dumps): start/quit, `⌘Space` and `⌘1…9` interception, Mission
  Control spreading and re-parking, desktop switching with `useSpaces`, Spotlight preference write and restore, window inspection of Calendar,
  VLC, Terminal, Dashlane, Notes, Mail, Finder, Safari, Preview, Teams, Zoom and VS Code. Not verified (no
  mouse or screen access in the dev session): title-bar drag swap, Chrome with several windows and
  Picture-in-Picture (Chrome was in native fullscreen), `⌘⌥N` with `useSpaces`, Zoom meetings, Xcode, a second display (self-tests
  only), and whether Spotlight visibly honours the category list. The `⌘Space` launcher was seen on screen with
  Spotlight staying closed; whether it holds keyboard focus right away on macOS 26 (the app activates itself from
  an event tap, which the system may grant late, so it asks twice) was checked only behind a locked screen.
- Title rules depend on the app's language; add your words to `floatTitles` if a secondary window still tiles.
