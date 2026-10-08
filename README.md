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
| `⌃⌥Tab` | previous workspace |
| `⌘Return` / `⌃⌥Return` | open a new Terminal window |
| `⇧⌘Return` | open Google Chrome |
| `⌃⌥R` / `⌃⌥P` | reload config / pause tiling |

## Mouse

Hold `⌘⌥` (`"mouseModifier"` in the config, `""` turns it off):

- **left drag** moves the window. A tiled window follows the pointer and, when dropped on another
  tile, swaps places with it; a floating window stays where you drop it.
- **right drag** resizes. For tiled windows the divider follows the pointer; floating windows grow
  from their top-left corner.

Option-letter combos are avoided on purpose: on a German keyboard `⌥L` types `@`.

## Layout rules

- A new window splits the focused one along its longer side (dwindle). Closing gives the space
  to its sibling.
- Workspaces 1–5 live on the main display, 6–9 on a second display (if none, on the main one).
- Inactive workspaces are parked at the bottom-right corner of the screen (1 px visible).
- Apps whose window cannot be resized, and the apps in `floatApps`, float.

## Config

`~/.config/hyprmac/config.json` is optional; everything missing falls back to the defaults.
`hyprmac --print-config` (binary inside the .app) prints the effective config.

```json
{
  "gap": 4,
  "outerGap": 6,
  "mainWorkspaces": 5,
  "floatApps": ["com.apple.calculator"],
  "passthroughApps": ["com.apple.Terminal"],
  "bindings": { "cmd-alt-return": "open Safari", "ctrl-alt-p": "" }
}
```

`passthroughApps`: no hotkey is intercepted while one of these is frontmost (e.g. apps where
`⌘1…9` must keep its own meaning). A binding set to `""` removes the default.
Actions: `workspace N`, `move-to-workspace N`, `focus|swap|resize <left|right|up|down>`,
`toggle-float`, `toggle-fullscreen`, `toggle-split`, `close`, `back-and-forth`, `reload`,
`pause`, `open <App name>`.

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
