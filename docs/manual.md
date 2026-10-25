# calmtile manual

Everything calmtile does, in one place. Nothing here is aspirational: each statement comes from the code
in `Sources/`. For the first ten minutes with the app read [first-steps.md](first-steps.md) instead.

## 1. The idea

calmtile keeps your screen tidy so you do not have to. Every window of a workspace gets a tile, tiles never
overlap, and the keyboard moves you between windows and workspaces. You stop arranging windows and keep
your attention on the work in them.

- **Dwindle layout.** The first window fills the workspace. Each new window splits the focused window along
  its longer side: side by side when it is wider than tall, stacked when it is taller than wide. Closing a
  window hands its space to the sibling it was split from. That is Hyprland's default layout.
- **Workspaces.** Nine of them, `⌘1…9`. A window belongs to exactly one workspace (or to the scratchpad).
- **Two ways to run workspaces.** By default all workspaces share one macOS desktop and the windows of
  inactive workspaces are parked just off the bottom-right corner (one pixel stays visible). With
  `"useSpaces": true` every workspace is a real macOS desktop instead; see [desktops.md](desktops.md).
- **Floating windows** sit on top of the tiles wherever you put them. Some windows float on their own
  (section 7); `⌃⌥T` floats or tiles the focused window by hand.
- **Fullscreen** (`⌃⌥F`) is calmtile's own: the window covers the workspace and the other tiles stay
  behind it. macOS native fullscreen (the green button) moves a window to its own Space and calmtile
  leaves it alone.

## 2. Install and permissions

```bash
scripts/build.sh install      # self-test, build, copy to ~/Applications
open ~/Applications/calmtile.app
```

calmtile needs two permissions, both under System Settings → Privacy & Security:

- **Accessibility**: to see and move windows. Without it calmtile shows an alert on start and does nothing.
- **Input Monitoring**: macOS may ask for it when the key tap is installed.

Grant them, then start calmtile again. The menu bar shows `▦ 1`: the current workspace. `▦ ⏸` means
tiling is paused, `🔒` that another app holds secure keyboard entry (section 10).

Start at login is off by default. The menu item **Start at login** (or `calmtile --install-login`) writes
`~/Library/LaunchAgents/local.calmtile.plist`; the same item removes it.

## 3. Keys

Default bindings. Every one of them can be changed or removed in the config (section 8).

### Workspaces

| Keys | Action | Example |
|---|---|---|
| `⌘1…9` | go to workspace N | `⌘2` shows workspace 2; in desktops mode a missing desktop is created |
| `⌘⌥1…9` | send the focused window to workspace N | `⌘⌥3` moves the window away; you stay where you are |
| `⌥Tab`, `⌃⌥Tab` | back to the previous workspace | press twice to return |
| `⌥⇧Tab` | move the current workspace to the next display | parked mode only |

### Focus, swap, resize

| Keys | Action | Example |
|---|---|---|
| `⌘←↑↓→`, `⌃⌥←↑↓→`, `⌃⌥H/J/K/L`, `⌥←↑↓→`, `⌥H/K` | focus the neighbour in that direction | with two windows side by side, `⌘→` focuses the right one |
| `⌃⌥⇧←↑↓→`, `⌥⇧←↑↓→` | swap with the neighbour | the two windows change places, sizes stay |
| `⌃⌥⌘←↑↓→` | move the nearest divider in that direction by 5 % | `⌃⌥⌘→` moves the divider right: the left window grows |
| `⌥-` / `⌥=` | shrink / grow the focused window along its split | |
| `⌃⌥S`, `⌥J` | flip the split that holds the focused window | side by side becomes stacked and back |

`⌘`-arrows and `⌥`-arrows are handed back to the app when there is no neighbour in that direction, so
`⌘←` still jumps to the start of the line in a text field at the left edge.

### Windows

| Keys | Action |
|---|---|
| `⌃⌥T`, `⌥V` | float the focused window, or tile it again |
| `⌃⌥F`, `⌥F` | fullscreen on this workspace, and back |
| `⌃⌥W`, `⌥W` | close the focused window (its close button is pressed) |
| `⌃⌥Q` | show or hide the scratchpad (section 6) |
| `⌃⌥⇧Q` | send the focused window to the scratchpad, or bring a shown scratchpad window back |

### Apps, launcher, themes

| Keys | Action |
|---|---|
| `⌘Return`, `⌃⌥Return` | a new Terminal window on this workspace |
| `⇧⌘Return` | Google Chrome (a new window when Chrome has none here) |
| `⌘Space` | the launcher restricted to applications (section 5) |
| `⌃⌥Space` | the full launcher: windows, apps, actions, themes |
| `⌃⌥⇧Space` | next theme |
| `⌃⌥R` | reload the config |
| `⌃⌥P` | pause tiling (windows are left alone) and resume |

### Mouse

Hold `⌘⌥` (`"mouseModifier"`):

- **left drag** moves a window. A tiled window follows the pointer and swaps places with the tile it is
  dropped on; a floating window stays where you drop it.
- **right drag** resizes: the dividers around a tiled window follow the pointer, a floating window grows
  from its top-left corner.

Without the modifier, a tiled window dragged by its title bar swaps with the tile it is dropped on or snaps
back; resizing a tiled window by its edge snaps back.

### Why these keys

The `⌃⌥` and `⌘` keys follow Omarchy (Hyprland with `Super`); the `⌥` keys are the AeroSpace defaults, so a
switch from AeroSpace needs no relearning. Option-letter combos beyond that set are avoided because on a
German keyboard `⌥L` types `@`.

## 4. Workspaces in detail

**Parked mode (default).** Switching is instant: the windows of the workspace you leave are moved to the
bottom-right corner, those of the target come back to their tiles. Workspaces 1…`mainWorkspaces` (5) live on
the main display, the rest on the second display; without a second display everything is on the main one.
`⌥⇧Tab` moves the current workspace to the next display. When Mission Control opens, every window is moved
to its layout position so the overview is readable, and parked again afterwards.

**Desktops mode (`"useSpaces": true`).** Workspace N is a macOS desktop; `⌘N` switches desktops through the
Dock, a missing desktop is created on the spot, numbers stay with their desktops even when macOS reorders
them, and windows always tile where they are. [desktops.md](desktops.md) has the mechanics and the limits
(no second display for workspaces 6–9, `⌘⌥N` drags the window with the system shortcut).

**Where a new window goes.** On the current workspace, split from the focused window. In parked mode a
window that would push a tile below `minTileWidth` × `minTileHeight` (420 × 280 px) opens on the next
workspace with room instead and calmtile switches there; in desktops mode it tiles here however small.

**Focus after a switch.** The window you used last on that workspace is focused. When the focused window
closes, focus returns to the last used window of the workspace, not to whatever macOS raises.

## 5. Launcher and themes

`⌃⌥Space` opens a search field. Typing filters by fuzzy match (letters in order; word starts and prefixes
score higher). Candidates: every open window (listed as "App – title", jumping there switches workspace),
every installed application (`/Applications`, `/System/Applications`, their `Utilities`,
`/System/Library/CoreServices`, `~/Applications`; a running app is activated, its windows stay where they
are, so pick the window entry to jump there), and calmtile actions: workspaces, move to workspace, float, fullscreen, flip split, close, scratchpad,
reload, pause, themes. `↑↓` or `Tab` select, `Return` runs, `Esc` or a click elsewhere closes.

`⌘Space` opens the same launcher with applications only. calmtile sees the key before Spotlight, so
Spotlight does not open while calmtile runs; nothing in the system is changed. To keep Spotlight, remove
the binding: `"bindings": {"cmd-space": ""}`.

Themes colour the border and the launcher: catppuccin (default), tokyo-night, gruvbox, nord, rose-pine,
everforest, kanagawa, catppuccin-latte. Pick one in the launcher (`Theme: …`) or cycle with `⌃⌥⇧Space`;
the choice is written to `~/.config/calmtile/theme` and wins over `"theme"` in the config.

**The border** outlines the focused window. It flashes for `borderFlash` seconds (0.6) when the focus moves
to another window and stays on during a mouse-modifier drag; `"borderFlash": 0` keeps it on all the time,
`"borderWidth": 0` turns it off. With gaps smaller than the border it is drawn inside the window edge.

## 6. Scratchpad

The scratchpad holds windows that belong to no workspace. `⌃⌥⇧Q` sends the focused window there: it
disappears. `⌃⌥Q` shows the most recent scratchpad window as a floating window in the middle of the
screen (70 % × 60 % of it) and hides it again on the next press. `⌃⌥⇧Q` on a shown scratchpad window
puts it back on the current workspace as a floating window; `⌃⌥T` tiles it. With an empty scratchpad `⌃⌥Q`
opens `"scratchpadApp"` (Terminal) and captures its first window: a drop-down terminal. The menu bar menu
lists scratchpad windows; clicking one shows it.

## 7. Which windows are managed

- Only windows whose Accessibility subrole is `AXStandardWindow`. Dialogs, sheets, floating panels,
  popovers, Picture-in-Picture, the Finder desktop and system prompts are never tiled, parked or moved.
- Standard windows that cannot be resized float at their own size.
- Standard windows without resize and without close or minimize buttons (transient popups) and every
  window of the apps in `ignoreApps` are not touched at all.
- The apps in `floatApps` float. `floatTitles` floats a window whose title contains one of the words given
  for its bundle id; the check runs until it matches, once per window, so `⌃⌥T` back to tiled sticks.
  Titles are compared in memory and never logged.
- Minimized windows and windows in native fullscreen are left alone.
- **Minimum sizes.** When an app refuses to shrink to its tile, calmtile remembers the size it insists on
  and gives it that room; the neighbours shrink. In parked mode a window whose minimum cannot sit beside its
  neighbours moves to the next workspace with room; in desktops mode, and when no workspace has room, it
  floats at its minimum size. Apps that snap their size to a grid (Terminal) are trimmed back into the tile.
- `passthroughApps`: while one of these is frontmost, calmtile intercepts no key at all. The default is a
  password manager, so nothing calmtile does can get between you and a password field.

**Finding a bundle id:** `osascript -e 'id of app "Calendar"'`.

## 8. Config

`~/.config/calmtile/config.json`, optional. Missing keys fall back to the defaults below. `⌃⌥R` or the
menu item **Reload config** applies changes; `calmtile --print-config` (the binary inside the .app) prints
the effective config, and a wrong value is reported in an alert.

| Key | Default | Meaning |
|---|---|---|
| `gap` | 4 | pixels between tiles |
| `outerGap` | 6 | pixels between the layout and the screen edge |
| `mainWorkspaces` | 5 | workspaces 1…N on the main display, the rest on a second one (parked mode) |
| `useSpaces` | false | workspaces are real macOS desktops |
| `minTileWidth`, `minTileHeight` | 420, 280 | smallest tile in parked mode; 0 turns the rule off |
| `theme` | `"catppuccin"` | default theme |
| `borderColor` | theme accent | `"#rrggbb"` |
| `borderWidth`, `borderRadius` | 3, 12 | border in pixels, 0 = no border |
| `borderFlash` | 0.6 | seconds the border shows after the focus moves; 0 = always on |
| `mouseModifier` | `"cmd-alt"` | modifier for mouse move and resize, `""` = off |
| `scratchpadApp` | `"Terminal"` | app opened by `⌃⌥Q` on an empty scratchpad |
| `spotlightAppsOnly` | false | restrict the system Spotlight to applications while running (section 9) |
| `floatApps` | System Settings, Calculator, Activity Monitor, Archive Utility, preference pane previews | bundle ids that float |
| `floatTitles` | VLC playlist/inspector/controller/equalizer/effects/messages windows, Chrome DevTools | `{"bundle id": ["word", …]}` |
| `ignoreApps` | system alert and authentication helpers | bundle ids never touched |
| `passthroughApps` | `["com.dashlane.dashlanephonefinal"]` | bundle ids with all keys left alone |
| `bindings` | the keys of section 3 | `{"combo": "action"}`; `""` removes a default |

Combos are written as modifiers and a key joined by `-`: `cmd`/`super`, `alt`/`opt`/`option`, `ctrl`,
`shift`, then one of `a`–`z`, `0`–`9`, `left right up down`, `return tab space escape delete`, `minus
equal comma period slash semicolon quote backslash backtick leftbracket rightbracket`. Keys are physical
ANSI positions, so a binding means the same key on every layout. A bare key without modifier is never bound.

Actions: `workspace N`, `move-to-workspace N`, `focus <left|right|up|down>`, `swap <dir>`, `resize <dir>`,
`resize-grow`, `resize-shrink`, `toggle-float`, `toggle-fullscreen`, `toggle-split`, `close`,
`back-and-forth`, `move-workspace-to-monitor`, `scratchpad`, `move-to-scratchpad`, `launcher`,
`app-launcher`, `theme <name>`, `theme-next`, `reload`, `pause`, `open <App name>`.

Example:

```json
{
  "gap": 0,
  "outerGap": 0,
  "useSpaces": true,
  "theme": "nord",
  "passthroughApps": ["com.dashlane.dashlanephonefinal", "com.apple.Terminal"],
  "bindings": { "cmd-alt-return": "open Safari", "cmd-space": "" }
}
```

## 9. Spotlight: applications only (system setting)

`"spotlightAppsOnly": true` (or the menu item **Spotlight: applications only**) makes the system Spotlight
list only applications while calmtile runs. This changes `orderedItems` in `com.apple.Spotlight`, the same
list as System Settings → Spotlight → Search Results, so: the current list is saved once to
`~/.config/calmtile/spotlight-backup.plist` and never overwritten; every category except applications is
switched off and the Spotlight process is restarted; the original is restored on quit (menu, `SIGTERM`,
`SIGINT`, `SIGHUP`), on pause and when the option is switched off. After a crash the next start, or
`calmtile --restore-spotlight`, restores it from the backup. Off by default, because the `⌘Space` launcher
does the job without touching the system.

## 10. Troubleshooting

**A hotkey does nothing.**

- The menu bar shows `🔒`: an app holds secure keyboard entry (a password field, a password manager,
  Terminal's "Secure Keyboard Entry"). macOS delivers keys to no hotkey tool at all; the menu names the app.
  Hotkeys return when it ends.
- A `passthroughApps` app is frontmost: by design.
- Another hotkey tool (AeroSpace, yabai, Karabiner, Raycast) started after calmtile and sees the key first.
  Run one.
- Tiling is paused (`▦ ⏸`): `⌃⌥P` resumes.
- In desktops mode a desktop is being created: the switch follows within a second.

**A window stays smaller or larger than its tile.** Larger: the app's minimum size, see section 7; the
neighbours should have made room, and in parked mode the window moves to a workspace with room. Smaller or
elsewhere: calmtile places it again on every tick until it matches; if it never does, the app refuses
Accessibility moves (look for `set ->` codes other than 0 in the debug log).

**A window floats that should tile.** It is not a standard window, cannot be resized, matches a
`floatTitles` word, or its app is in `floatApps`. `⌃⌥T` tiles it for this session; the config rule decides
the next time.

**Windows flash at their own size before they are tiled.** Expected to a small degree: the app draws its
first frame before calmtile can move it. New windows are placed from the creation notification to keep it
short; apps that restore their last frame open in place.

**The focus border is drawn around nothing.** It follows the focused window; if that window is on another
desktop (desktops mode) it hides. Report it if it stays.

**Log.** `~/Library/Logs/calmtile.log`: window counts, actions, permission state, desktop re-homings, and
every step of the loop that took long, with the app it waited on. Window titles are never written.
`CALMTILE_DEBUG=1` in the environment adds placements with frames.

## 11. Undo everything

- **Pause:** `⌃⌥P` or the menu item. Windows stay where they are; nothing is intercepted except `⌃⌥P`.
- **Quit:** the menu item **Quit calmtile** (`⌘Q` in the menu). The Spotlight setting is restored if it was
  changed. Parked windows stay parked at the corner until you move them; the easiest way is to start
  calmtile again and press `⌘1…9`, or to drag them back.
- **Login item:** the menu item **Start at login** (`calmtile --uninstall-login`).
- **Settings and state:** `~/.config/calmtile/` (config, theme, desktop numbers, Spotlight backup) and
  `~/Library/Logs/calmtile.log`. Delete them and calmtile starts from the defaults.
- **Permissions:** remove calmtile under System Settings → Privacy & Security → Accessibility and Input
  Monitoring.
- **The app:** delete `~/Applications/calmtile.app`.

## 12. Command-line switches

Run through the binary inside the bundle (`~/Applications/calmtile.app/Contents/MacOS/calmtile`) or, for
anything that needs the Accessibility grant, through `open -g -n -a ~/Applications/calmtile.app --args …`:

| Switch | Does |
|---|---|
| `--print-config` | print the effective config as JSON |
| `--install-login`, `--uninstall-login` | write or remove the LaunchAgent |
| `--restore-spotlight` | put the Spotlight categories back from the backup |
| `--dump-windows` | one line per window of every app: role, subrole, resizable, buttons, size; never the title |
| `--post-key <combo>` | synthesize a key press for the running instance (test aid) |
| `--remove-desktop N`, `--dump-dock`, `--probe-switch N`, `--probe-hotkey-switch N` | desktops-mode test aids, see [development.md](development.md) |
