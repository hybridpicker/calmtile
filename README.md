# calmtile

A keyboard-driven tiling window manager for macOS: Hyprland's dwindle layout, workspaces on `⌘1…9`, and an
app launcher on `⌘Space`.

<!-- IMAGES -->

[![build](https://github.com/hybridpicker/calmtile/actions/workflows/build.yml/badge.svg)](https://github.com/hybridpicker/calmtile/actions/workflows/build.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey)

## Why calmtile

New windows split the focused one and closed windows give their space back, so you stop pushing windows
around. The keys use `⌘` and `⌃⌥`, as on a Mac, instead of a separate modifier you have to learn. It needs no
SIP changes and no kernel extension, only the Accessibility API and a key tap, and it is small enough to read
(18 Swift files, no dependencies).

## Status

A personal daily driver, young, with rough edges:

- Tested only on **macOS 26 (Tahoe), Apple silicon, one display**. The build targets macOS 14, but nothing
  below 26 and no Intel Mac has been tried. A second display is covered by self-tests only.
- **There is no finished app.** No Developer ID signing, no notarisation, no release download. You build it
  from source with the Xcode Command Line Tools.
- It uses **private window server calls** (`CGS…` functions, `_AXUIElementGetWindow`) for real macOS
  desktops. Apple can change or remove them in any macOS update.
- What has and has not been verified live is listed in [docs/development.md](docs/development.md#what-has-been-verified-live).

## Features

- **Dwindle tiling.** A new window splits the focused one along its longer side. Gaps, a border on the
  focused window, eight themes.
- **Nine workspaces.** Either *parked* (default: other workspaces are moved off screen, no macOS desktops
  involved) or real macOS desktops with `"useSpaces": true` ([how](docs/desktops.md)).
- **Keyboard focus, swap and resize**, and `⌘⌥` + mouse drag to move or resize.
- **Launchers.** `⌘Space` lists applications only; `⌃⌥Space` lists windows, applications, actions and themes.
- **Scratchpad** and a drop-down terminal.
- **Per-app rules.** Float, ignore, pass keys through, float by window title. Only standard windows are
  managed; dialogs, sheets and system prompts are left alone.

## Install

```bash
xcode-select --install        # once, if you have no compiler yet
git clone https://github.com/hybridpicker/calmtile.git && cd calmtile
scripts/build.sh install      # self-test, build, copy to ~/Applications
open ~/Applications/calmtile.app
```

On the first start, allow calmtile under System Settings → Privacy & Security → **Accessibility** (and
**Input Monitoring** if macOS asks), then start it again. Without an "Apple Development" certificate the build
is signed ad hoc, and macOS asks for Accessibility again after every rebuild. Run only one hotkey or tiling
tool at a time. [First steps](docs/first-steps.md) walks through the first ten minutes.

## Keys

| Keys | Action |
|---|---|
| `⌘1…9` / `⌘⌥1…9` | switch workspace / send the focused window there |
| `⌘←↑↓→` or `⌃⌥←↑↓→` | focus the neighbour |
| `⌃⌥⇧←↑↓→` | swap with the neighbour |
| `⌃⌥F` / `⌃⌥T` / `⌃⌥S` | fullscreen / float / flip split |
| `⌃⌥W` | close the window |
| `⌘Return` | open a new Terminal window |
| `⌘Space` / `⌃⌥Space` | applications / windows, apps, actions, themes |
| `⌃⌥Q` | show or hide the scratchpad |
| `⌃⌥R` / `⌃⌥P` | reload the config / pause tiling |

Every binding can be changed in the config; the full list is in the [manual](docs/manual.md#3-keys).

## Config

`~/.config/calmtile/config.json` is optional. Missing keys fall back to the defaults, and
`calmtile --print-config` (the binary inside the .app) prints the effective config.

```json
{
  "gap": 8,
  "theme": "nord",
  "useSpaces": false,
  "floatApps": ["com.apple.systempreferences", "com.apple.calculator"],
  "bindings": { "cmd-alt-return": "open Safari", "ctrl-alt-p": "" }
}
```

A list replaces its default instead of adding to it; `bindings` are merged. All keys, the combo syntax and the
actions are in the [config reference](docs/manual.md#8-config).

## Compared with AeroSpace and HyprMac

[AeroSpace](https://github.com/nikitabobko/AeroSpace) (i3-like, configured in a file and driven by a
command line client) and [HyprMac](https://github.com/zacharytgray/HyprMac) (Hyprland-inspired, with a DMG and
a Homebrew cask) are packaged, have users, and have been through more macOS versions than calmtile. Choose one
of them if you want something finished. calmtile is for you if you want the dwindle layout on `⌘` keys with a
launcher built in, workspaces that can be real macOS desktops, and you are willing to build from source and
accept a one-person project.

## Known limits

- Windows are moved after they open (there is no compositor), so a new window is drawn at its own size first.
  Measured for Terminal: 0.24 to 0.5 s, including macOS's opening animation.
- A window whose minimum size cannot sit beside its neighbours floats, after calmtile has tried flipping
  splits to make room (desktops mode; parked mode moves it to the next workspace). Four large windows on one
  desktop of a 1440 pt wide display are about the limit.
- Resizing a tiled window by its edge snaps back; use the mouse modifier and right drag.
- macOS native fullscreen is switched off for managed windows (`exitFullscreen`): the window leaves it again
  at once. Apps in `fullscreenApps` (Claude Desktop) keep it. The window buttons themselves cannot be hidden.
- Real desktops: macOS has no call to move a window to another desktop, so `⌘⌥N` drags it with the system
  shortcut. Creating and removing a desktop goes through Mission Control, which shows for about a second.
  Desktop numbers stay with their desktop and may differ from the order in Mission Control
  ([why](docs/desktops.md#numbers-stay-with-their-desktops)).
- The full list of what has not been verified yet is in [docs/development.md](docs/development.md#what-has-been-verified-live).

## Privacy

A key tap and Accessibility access could, technically, read every key you type and the titles and contents of
every window. What calmtile does with them, so that you can check it in the code:

- **Keys.** The tap (`Sources/calmtile/Hotkeys.swift`) reads the key code and the modifiers of each event and
  compares them with the binding table. Nothing is stored. While a password manager or any app in
  `passthroughApps` is frontmost, no key is touched, and while secure keyboard entry is on, macOS delivers no keys to the tap at all.
- **Window titles** are read for the launcher list and the title rules only. They are never written to the
  log or to a file.
- **Log.** `~/Library/Logs/calmtile.log` holds window counts, action names, permission state and bundle ids.
- **Network.** The source contains no network code (no `URLSession`, sockets or `Network` framework; search
  for them). The only programs it starts are `/usr/bin/open` (for `open <App>` bindings and the login item)
  and `/usr/bin/killall` (to restart Spotlight when you switch on `spotlightAppsOnly`).
- **Files it writes:** the log, `~/.config/calmtile/desktops.json` (desktop numbers),
  `launcher-usage.json` (how often you start each app, by name), the LaunchAgent if you enable start at
  login, and the Spotlight preference if you enable `spotlightAppsOnly` (restored on quit).

## Documentation

- [First steps](docs/first-steps.md): install to a working setup in ten minutes.
- [Manual](docs/manual.md): every key, option, rule and switch, with troubleshooting and
  [how to undo everything](docs/manual.md#11-undo-everything).
- [Real desktops](docs/desktops.md): how `"useSpaces"` works.
- [Development](docs/development.md): build, log, test aids, what has been verified.
- [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), [Changelog](CHANGELOG.md).

## License

[MIT](LICENSE).
