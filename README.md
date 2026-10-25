# calmtile

A calm screen for focused work on macOS. Windows arrange themselves in Hyprland's dwindle layout, workspaces
sit on `⌘1…9`, the keyboard moves you between windows, and `⌘Space` opens what you need. You stop pushing
windows around and keep your attention on the work in them. A small menu bar app; no SIP changes, no kernel
extension, just the Accessibility API and a key tap.

New here? [First steps](docs/first-steps.md) takes you from install to a self-arranging workspace in ten
minutes; the [manual](docs/manual.md) has everything else.

## What it does

- **Dwindle tiling.** A new window splits the focused one along its longer side; closing a window
  gives its space to the sibling. Gaps, a focused-window border and themes (catppuccin, tokyo-night,
  gruvbox, nord, rose-pine, everforest, kanagawa, catppuccin-latte).
- **Workspaces on `⌘1…9`**, `⌘⌥1…9` to send a window there, `⌥Tab` to go back. Two ways to run them:
  parked (default, no macOS Spaces involved) or on real macOS desktops (`"useSpaces": true`), see
  [Workspaces](#workspaces).
- **Keyboard focus, swap and resize**, plus `⌘⌥` + mouse drag to move or resize.
- **Launcher** (`⌃⌥Space`) for windows, apps, actions and themes; an applications-only launcher on
  `⌘Space` that takes the key from Spotlight while calmtile runs.
- **Scratchpad** and a drop-down terminal (`⌃⌥Q`).
- **Per-app rules**: float, ignore, pass keys through, float by window title. Only standard windows are
  managed; dialogs, sheets, popovers and system prompts are never touched.
- **Workspace keys win over app shortcuts** (`⌘1` switches workspace even in Chrome), and the key tap
  runs on its own thread, so a stuck app cannot make a key leak through.

## First 10 minutes

Build and start it, grant Accessibility, press `⌘Return` twice and watch the two windows share the
screen. `⌘2` gives you an empty workspace, `⌘⌥2` sends a window there, `⌘←→` moves the focus, `⌘Space`
opens an app. [First steps](docs/first-steps.md) walks through exactly that, with what to expect at each
step and what it means when something else happens.

## Status

A personal daily driver on macOS 26 (Tahoe), one display, Apple silicon, built with the Xcode Command
Line Tools only. It is young: expect rough edges, read [Known limits](#known-limits), and see
[docs/development.md](docs/development.md) for what has actually been verified and how.

If you want a mature, packaged tiling manager, look at [AeroSpace](https://github.com/nikitabobko/AeroSpace)
(i3-like, CLI-driven, large community) or [HyprMac](https://github.com/zacharytgray/HyprMac) (Hyprland-like,
DMG and Homebrew, auto-updates). calmtile is for people who want the dwindle layout with `⌘` keys and a
launcher built in, who are happy to build from source, and who care about workspaces on real macOS desktops.

## Install

Requirements: macOS 11 or later (developed and tested on macOS 26), Xcode Command Line Tools
(`xcode-select --install`).

```bash
git clone https://github.com/hybridpicker/calmtile.git
cd calmtile
scripts/build.sh install      # self-test, build, copy to ~/Applications
open ~/Applications/calmtile.app
```

On the first start allow calmtile under System Settings → Privacy & Security → **Accessibility** (and
**Input Monitoring** if macOS asks), then start it again. The menu bar shows `▦ <workspace>` (`▦ ⏸`
while paused, `🔒` while secure keyboard entry blocks all hotkeys).

Run only one hotkey or tiling tool at a time (AeroSpace, yabai, Karabiner bindings on the same keys):
whichever tool installed its key tap last sees a key first.

**Start at login** is off by default; the menu item "Start at login" (or `calmtile --install-login` /
`--uninstall-login`) writes or removes `~/Library/LaunchAgents/local.calmtile.plist`.

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
| `⌘Space` | applications launcher (replaces Spotlight while calmtile runs) |
| `⌃⌥Space` | launcher: windows, apps, actions and themes |
| `⌃⌥⇧Space` | next theme |
| `⌃⌥R` / `⌃⌥P` | reload config / pause tiling |

Every binding can be changed or removed in the config (see [Config](#config)). Option-letter combos
beyond the AeroSpace set are avoided on purpose: on a German keyboard `⌥L` types `@`.

### Mouse

Hold `⌘⌥` (`"mouseModifier"` in the config, `""` turns it off):

- **left drag** moves the window. A tiled window follows the pointer and, when dropped on another
  tile, swaps places with it; a floating window stays where you drop it.
- **right drag** resizes. For tiled windows the divider follows the pointer; floating windows grow
  from their top-left corner.

A tiled window dragged by its plain title bar swaps with the tile it is dropped on, or snaps back.

## Workspaces

**Parked (default).** All workspaces live on one macOS Space; the windows of inactive workspaces are
parked at the bottom-right corner of the screen with one pixel showing. Switching is instant and needs
nothing from macOS. Workspaces 1–5 live on the main display, 6–9 on a second one (`"mainWorkspaces"`;
without a second display all are on the main one). While Mission Control is open, calmtile moves every
window to its layout position so the overview looks right, and parks them again afterwards.

**Real desktops (`"useSpaces": true`).** Workspace N is a macOS desktop: `⌘N` switches desktops the
way the Dock does, Mission Control shows a clean desktop per workspace, nothing is parked. A missing
desktop is created when you go there (Hyprland semantics), numbers stay with their desktops even with
"Automatically rearrange Spaces" on, and windows always tile on their desktop. macOS gives no public
way to move a window to another desktop, so `⌘⌥N` drags it there with the system shortcut, and
workspaces 6–9 do not move to a second display in this mode. The details, and why switching has to go
through the Dock, are in [docs/desktops.md](docs/desktops.md).

## Launcher and themes

`⌃⌥Space` opens a search field: type to filter open windows (jump there), installed apps and
calmtile actions (workspaces, float, themes …); `↑↓`/`Tab` select, `Return` runs, `Esc` closes.
`⌘Space` opens the same launcher restricted to applications. calmtile sees the key before Spotlight,
so Spotlight does not open while calmtile runs and no system setting is touched; remove the binding
with `"bindings": {"cmd-space": ""}` to get Spotlight back.

Themes colour the focused-window border and the launcher. Pick one in the launcher (`Theme: …`) or
cycle with `⌃⌥⇧Space`; the choice is kept in `~/.config/calmtile/theme`. `"theme"` in the config sets
the default, `"borderColor": "#rrggbb"` overrides the border colour, `"borderWidth": 0` turns the border off.
The border flashes for `borderFlash` seconds (default 0.6) whenever the focus moves to another window, and stays on
while you drag a window with the mouse modifier; `"borderFlash": 0` keeps it on all the time. On a desktop switch it
goes at once and the newly focused window flashes when the desktop has arrived.

## Scratchpad

`⌃⌥⇧Q` sends the focused window to the scratchpad: it disappears and belongs to no workspace.
`⌃⌥Q` pops the latest one up as a floating window in the middle of the screen (and hides it
again). With an empty scratchpad `⌃⌥Q` opens `"scratchpadApp"` (default Terminal) and captures
its window, which makes a drop-down terminal. `⌃⌥⇧Q` on a shown scratchpad window puts it
back on the current workspace. The menu bar lists scratchpad windows too.

## Window rules

- Only `AXStandardWindow` windows are managed. Dialogs, sheets, floating panels, popovers,
  Picture-in-Picture, the Finder desktop and system dialogs are not standard windows and are never
  tiled, parked or moved.
- Standard windows that cannot be resized float; so do the apps in `floatApps` (System Settings,
  Calculator, Activity Monitor, Archive Utility by default).
- Standard windows with no resize and no close/minimize button (transient popups) and the apps in
  `ignoreApps` (system alert helpers) are not touched at all.
- `floatTitles` (`{"bundle id": ["word", …]}`): standard windows whose title contains a word float
  (VLC playlist/inspector/controller and Chrome DevTools by default). Checked until it matches, once
  per window, so a manual `⌃⌥T` back to tiled sticks. Titles are only compared in memory, never
  logged. Title rules depend on the app's language; add your words if a secondary window still tiles.
- `passthroughApps`: no hotkey is intercepted while one of these is frontmost (a password manager by
  default, so nothing calmtile does can interfere with its input).
- calmtile learns the minimum size an app insists on and gives that window the room (neighbours
  shrink). In parked mode a tile is never split below `minTileWidth` × `minTileHeight` (420 × 280 px,
  0 turns it off): a window that would not fit opens on the next workspace with room and calmtile
  switches there. Apps that snap their size to a grid (Terminal) are trimmed back into their tile.

### Key conflicts with apps

calmtile takes every bound key out of the event stream before the focused app sees it, so `⌘1…9`
switches workspace even in Chrome (tab 1…9) and Terminal (window 1…9); the apps' own shortcuts need
no change. Use `⌃Tab` / `⌃⇧Tab` or `⌘⌥←/→` for Chrome tabs, `` ⌘` `` for Terminal windows. To give an
app its keys back completely, add its bundle id to `passthroughApps`.

When a hotkey "does nothing", one of these is the reason:

- **Secure keyboard entry** is on: a password field, a password manager or Terminal's "Secure Keyboard
  Entry" menu item. macOS then delivers keys to no hotkey tool at all. The menu bar shows `▦ 2 🔒`,
  the menu names the app holding it, and the log says `secure keyboard entry on`.
- Another hotkey tool started after calmtile grabs the same key. Run only one.
- With `"useSpaces": true`, the desktop is being created; the switch follows within a second.

## Config

`~/.config/calmtile/config.json` is optional; everything missing falls back to the defaults.
`calmtile --print-config` (the binary inside the .app) prints the effective config.

```json
{
  "gap": 4,
  "outerGap": 6,
  "mainWorkspaces": 5,
  "useSpaces": false,
  "minTileWidth": 420,
  "minTileHeight": 280,
  "theme": "catppuccin",
  "borderWidth": 3,
  "borderRadius": 12,
  "borderFlash": 0.6,
  "mouseModifier": "cmd-alt",
  "scratchpadApp": "Terminal",
  "spotlightAppsOnly": false,
  "floatApps": ["com.apple.calculator"],
  "floatTitles": { "org.videolan.vlc": ["Playlist"] },
  "ignoreApps": ["com.apple.SecurityAgent"],
  "passthroughApps": ["com.apple.Terminal"],
  "bindings": { "cmd-alt-return": "open Safari", "ctrl-alt-p": "" }
}
```

| Key | Default | Meaning |
|---|---|---|
| `gap`, `outerGap` | 4, 6 | pixels between tiles and around the layout |
| `mainWorkspaces` | 5 | workspaces 1…N live on the main display, the rest on a second one (parked mode) |
| `useSpaces` | false | workspaces are real macOS desktops ([docs/desktops.md](docs/desktops.md)) |
| `minTileWidth`, `minTileHeight` | 420, 280 | smallest tile in parked mode; 0 turns the rule off |
| `theme`, `borderColor`, `borderWidth`, `borderRadius` | catppuccin, theme accent, 3, 12 | focused-window border and launcher colours |
| `borderFlash` | 0.6 | seconds the border shows after the focus moves to another window; 0 = always on |
| `mouseModifier` | `cmd-alt` | modifier for mouse move/resize, `""` off |
| `scratchpadApp` | Terminal | app opened by `⌃⌥Q` on an empty scratchpad |
| `spotlightAppsOnly` | false | restrict system Spotlight to applications while running (changes a system setting, see below) |
| `floatApps`, `floatTitles`, `ignoreApps`, `passthroughApps` | see [Window rules](#window-rules) | per-app behaviour, by bundle id |
| `bindings` | see [Default keys](#default-keys) | `"combo": "action"`; `""` removes a default |

Key combos are written like `cmd-alt-1`, `ctrl-alt-shift-left`, `alt-tab` (physical ANSI key
positions, so they are the same on every layout). Actions: `workspace N`, `move-to-workspace N`,
`focus|swap|resize <left|right|up|down>`, `resize-grow`, `resize-shrink`, `toggle-float`,
`toggle-fullscreen`, `toggle-split`, `close`, `back-and-forth`, `move-workspace-to-monitor`,
`scratchpad`, `move-to-scratchpad`, `launcher`, `app-launcher`, `theme <name>`, `theme-next`,
`reload`, `pause`, `open <App name>`.

### Spotlight: applications only (system setting, opt-in)

`"spotlightAppsOnly": true` makes the system Spotlight list only applications while calmtile runs.
This **changes a system setting** (`orderedItems` in `com.apple.Spotlight`, the same list as System
Settings → Spotlight → Search Results), so calmtile handles it carefully: on start the current list is
saved to `~/.config/calmtile/spotlight-backup.plist` and never overwritten, every category except
applications is switched off and the Spotlight process is restarted; on quit, on pause and when the
option is switched off again the original is restored (after a crash, the next start or
`calmtile --restore-spotlight` restores it). The default is off, because the `⌘Space` launcher does
the job without touching the system.

## Known limits

- Windows are moved by the app after they open (there is no compositor), so a short flicker remains
  possible; new windows are placed from the creation notification to keep it short.
- A window whose minimum size cannot sit beside its neighbours floats; two such windows cannot share a
  1440 px wide workspace.
- Resizing a tiled window by its edge snaps back; use the mouse modifier + right drag to move dividers.
- macOS native fullscreen windows are left alone (they live on their own Space).
- Real desktops: macOS offers no way to move a window to another desktop, so `⌘⌥N` works by dragging
  it with the system shortcut; windows never overflow to another desktop.
- A second display is covered by self-tests only so far.

## How it works

- `Sources/CalmCore` holds the dwindle tree, workspaces, focus and the layout decisions. It knows nothing
  about macOS (windows are ids, frames are rectangles) and is covered by the self-test in
  `Sources/calmcore-selftest`, which `scripts/build.sh` runs before every build.
- `Sources/calmtile` is the app: windows through the Accessibility API, a `CGEventTap` on its own thread
  for the keys, the menu bar, the launcher, config, themes, the login item and, for real desktops, the
  window server's Space calls that other tiling tools use as well.

[docs/development.md](docs/development.md) has the build details, the debug log, the test aids and
the list of what has been verified live.

## License

[MIT](LICENSE).
