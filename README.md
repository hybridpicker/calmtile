# hyprmac

A small macOS menu bar app that tiles windows like Hyprland's dwindle layout and switches
workspaces with `Cmd+1…9`. Replaces AeroSpace (do not run both).

## Build and run

```bash
scripts/build.sh install      # self-test, build, copy to ~/Applications
open ~/Applications/hyprmac.app
```

First start: allow it under System Settings → Privacy & Security → **Accessibility**
(and **Input Monitoring** if macOS asks), then start it again. The menu bar shows `▦ <workspace>`.

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
| `⌥-` / `⌥=` | shrink / grow the focused window |
| `⌥J` / `⌥W` / `⌥F` / `⌥V` | flip split / close / fullscreen / float (AeroSpace keys) |
| `⌘Return` / `⌃⌥Return` | open a new Terminal window |
| `⇧⌘Return` | open Google Chrome |
| `⌃⌥Q` / `⌃⌥⇧Q` | show/hide the scratchpad / send the focused window there |
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
- Dashlane is in `passthroughApps` by default: no hotkey is intercepted while it is frontmost.
- Inspect real windows (no titles are printed):
  `open -n -a ~/Applications/hyprmac.app --stdout out.txt --args --dump-windows`.

### Key conflicts with apps

Workspace keys win everywhere, as in the AeroSpace setup: `⌘1…9` switches workspace even in Chrome
(tab 1…9) and Terminal (window 1…9). Use `⌃Tab` / `⌃⇧Tab` or `⌘⌥←/→` for Chrome tabs, `⌘\`` for Terminal
windows. To give an app its keys back completely, add its bundle id to `passthroughApps`
(`com.google.Chrome`, `com.apple.Terminal`); that disables all hyprmac hotkeys while it is frontmost.

## Config

`~/.config/hyprmac/config.json` is optional; everything missing falls back to the defaults.
`hyprmac --print-config` (binary inside the .app) prints the effective config.

```json
{
  "gap": 4,
  "outerGap": 6,
  "mainWorkspaces": 5,
  "spotlightAppsOnly": true,
  "floatApps": ["com.apple.calculator"],
  "ignoreApps": ["com.apple.SecurityAgent"],
  "passthroughApps": ["com.apple.Terminal"],
  "bindings": { "cmd-alt-return": "open Safari", "ctrl-alt-p": "" }
}
```

`passthroughApps`: no hotkey is intercepted while one of these is frontmost (e.g. apps where
`⌘1…9` must keep its own meaning). A binding set to `""` removes the default.
Actions: `scratchpad`, `move-to-scratchpad`, `launcher`, `theme <name>`, `theme-next`, `workspace N`, `move-to-workspace N`, `focus|swap|resize <left|right|up|down>`,
`resize-grow`, `resize-shrink`, `toggle-float`, `toggle-fullscreen`, `toggle-split`, `close`, `back-and-forth`, `reload`,
`pause`, `open <App name>`.

## Start at login

Off by default. The menu item "Start at login" (or `hyprmac --install-login` / `--uninstall-login`)
writes/removes `~/Library/LaunchAgents/local.hyprmac.plist`, which opens `~/Applications/hyprmac.app`.

## Spotlight: applications only

While hyprmac runs, `⌘Space` Spotlight lists only applications (no documents, mail, folders …).
This **changes a system setting** (`orderedItems` in `com.apple.Spotlight`, the same list as System
Settings → Spotlight → Search Results), so hyprmac handles it carefully:

- On start the current list (or "key not set") is saved to `~/.config/hyprmac/spotlight-backup.plist`,
  every category except `APPLICATIONS` is switched off, and the Spotlight UI process is restarted.
- It is **reset to the original on quit** (menu, `SIGTERM`/`SIGINT`/`SIGHUP`), on **pause**, and when
  `"spotlightAppsOnly": false` is set and reloaded. A backup that already exists is never overwritten, so after a
  crash the next start (or `hyprmac --restore-spotlight`) still restores the true original.
- `"spotlightAppsOnly": false` (default `true`) disables it; the menu item "Spotlight: applications only"
  toggles it for the current run.
- Not verified visually on macOS 26.5: the preference write and restore were checked with `defaults`; whether
  Spotlight honours the key was not observed (no screen access in the dev session). If categories still show,
  restore with `hyprmac --restore-spotlight` and set `"spotlightAppsOnly": false`.

## Structure

- `Sources/HyprCore` – dwindle tree, workspaces, focus; no AppKit, self-tested (`hyprcore-selftest`).
- `Sources/hyprmac` – Accessibility windows, key tap, config, menu bar.

## Known limits

- Apps with a minimum size (Terminal, Chrome) cannot always shrink to the tile; they overlap.
- Windows are moved by the app after they open (no compositor), so there is a short flicker.
- Windows are re-placed when the plan changes, not when you drag them; a dragged tiled window
  snaps back after the next layout change.
- macOS native fullscreen windows are left alone.
- Not run on a live session yet: only the layout core is covered by tests.
