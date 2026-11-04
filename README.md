# calmtile

A calm screen for focused work on macOS. Windows arrange themselves in Hyprland's dwindle layout, workspaces
sit on `⌘1…9`, the keyboard moves you between windows, and `⌘Space` opens what you need. You stop pushing
windows around and keep your attention on the work in them. A small menu bar app; no SIP changes, no kernel
extension, just the Accessibility API and a key tap.

New here? [First steps](docs/first-steps.md) takes you from install to a self-arranging workspace in ten
minutes; the [manual](docs/manual.md) has everything else.

## What it does

- **Dwindle tiling.** A new window splits the focused one along its longer side; closing a window gives
  its space to the sibling. Gaps, a focused-window border and eight themes.
- **Workspaces on `⌘1…9`**, `⌘⌥1…9` to send a window there. Parked (default, no macOS Spaces involved) or
  on real macOS desktops (`"useSpaces": true`, see [docs/desktops.md](docs/desktops.md)).
- **Keyboard focus, swap and resize**, plus `⌘⌥` + mouse drag to move or resize.
- **Launcher** (`⌃⌥Space`) for windows, apps, actions and themes, and an applications-only launcher on
  `⌘Space` that takes the key from Spotlight while calmtile runs.
- **Scratchpad** and a drop-down terminal (`⌃⌥Q`).
- **Per-app rules**: float, ignore, pass keys through, float by window title, tile fixed-size windows (the
  iOS Simulator) at their own size. Only standard windows are
  managed; dialogs, sheets, popovers and system prompts are never touched.
- **Workspace keys win over app shortcuts** (`⌘1` switches workspace even in Chrome), and the key tap runs
  on its own thread, so a stuck app cannot make a key leak through.

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

Requirements: macOS 14 or later (developed and tested only on macOS 26 with Apple silicon), Xcode Command Line Tools
(`xcode-select --install`).

```bash
git clone https://github.com/hybridpicker/calmtile.git
cd calmtile
scripts/build.sh install      # self-test, build, copy to ~/Applications
open ~/Applications/calmtile.app
```

On the first start allow calmtile under System Settings → Privacy & Security → **Accessibility** (and
**Input Monitoring** if macOS asks), then start it again. The build is signed with your "Apple Development"
certificate if you have one; otherwise it is signed ad hoc and macOS asks for Accessibility again after every
rebuild (remove the old entry in that list first). Built on your Mac, the app is not quarantined, so Gatekeeper
does not get in the way. The menu bar shows `▦ <workspace>` (`▦ ⏸` while paused, `🔒` while secure keyboard
entry blocks all hotkeys).

Run only one hotkey or tiling tool at a time (AeroSpace, yabai, Karabiner bindings on the same keys):
whichever tool installed its key tap last sees a key first.

**Start at login** is off by default; the menu item "Start at login" (or `calmtile --install-login` /
`--uninstall-login`) writes or removes `~/Library/LaunchAgents/local.calmtile.plist`. To remove calmtile
completely, see [Undo everything](docs/manual.md#11-undo-everything).

## The keys you need first

| Keys | Action |
|---|---|
| `⌘1…9` / `⌘⌥1…9` | switch workspace / send the focused window there |
| `⌘←↑↓→` or `⌃⌥←↑↓→` | focus the neighbour (`⌘`-arrows pass through when there is no neighbour) |
| `⌃⌥⇧←↑↓→` | swap with the neighbour |
| `⌃⌥F` / `⌃⌥T` / `⌃⌥S` | fullscreen / float / flip split |
| `⌃⌥W` | close the window |
| `⌥Tab` | back to the previous workspace |
| `⌘Return` | open a new Terminal window |
| `⌘Space` / `⌃⌥Space` | applications launcher / windows, apps, actions and themes |
| `⌃⌥Q` | show or hide the scratchpad |
| `⌃⌥R` / `⌃⌥P` | reload the config / pause tiling |

Every binding can be changed or removed in the config. The full list, the AeroSpace-style `⌥` keys and
the mouse gestures are in the [manual](docs/manual.md#3-keys). Option-letter combos beyond the AeroSpace
set are avoided on purpose: on a German keyboard `⌥L` types `@`.

## Config

`~/.config/calmtile/config.json` is optional; everything missing falls back to the defaults, and
`calmtile --print-config` (the binary inside the .app) prints the effective config.

```json
{
  "gap": 4,
  "theme": "catppuccin",
  "useSpaces": false,
  "floatApps": ["com.apple.systempreferences", "com.apple.calculator", "com.apple.Music"],
  "bindings": { "cmd-alt-return": "open Safari", "ctrl-alt-p": "" }
}
```

A list replaces its default rather than adding to it; `bindings` are merged. Every key with its default, the key-combo syntax and
the list of actions are in the
[config reference](docs/manual.md#8-config). The opt-in "Spotlight: applications only" switch has its
[own section](docs/manual.md#9-spotlight-applications-only-system-setting): it changes a system setting
and restores it afterwards.

## Known limits

- Windows are moved after they open (there is no compositor): a new window is drawn at its own size first.
  Measured for Terminal: 0.24-0.5 s, including macOS's opening animation.
- A window whose minimum size cannot sit beside its neighbours floats; two such windows cannot share a
  1440 px wide workspace.
- Resizing a tiled window by its edge snaps back; use the mouse modifier + right drag to move dividers.
- macOS native fullscreen windows are left alone (they live on their own Space).
- Real desktops: macOS offers no way to move a window to another desktop, so `⌘⌥N` works by dragging
  it with the system shortcut; windows never overflow to another desktop. Creating a desktop (`⌘N` on a
  missing one) and removing an empty one (`removeEmptyDesktops`) go through Mission Control, which shows
  for about a second.
- A second display is covered by self-tests only so far.

## How it works

- `Sources/CalmCore` holds the dwindle tree, workspaces, focus and the layout decisions. It knows nothing
  about macOS (windows are ids, frames are rectangles) and is covered by the self-test in
  `Sources/calmcore-selftest`, which `scripts/build.sh` runs before every build.
- `Sources/calmtile` is the app: windows through the Accessibility API, a `CGEventTap` on its own thread
  for the keys, the menu bar, the launcher, config, themes, the login item and, for real desktops, the
  window server's Space calls that other tiling tools use as well.
- The loop never waits on an app from the main thread the keys depend on: the windows are listed on a
  thread of their own, an app is asked again only when the window server shows a change or the app sends a
  notification, a call into an app gives up after 150 ms, and an app that keeps not answering is left
  alone for a few seconds. When nothing happens the loop ticks once a second.

## Documentation

- [First steps](docs/first-steps.md): install to a working setup in ten minutes.
- [Manual](docs/manual.md): every key, option, rule and switch, with troubleshooting and undo.
- [Real desktops](docs/desktops.md): how `"useSpaces"` works and why switching goes through the Dock.
- [Development](docs/development.md): build details, debug log, test aids and what has been verified live.
- [Changelog](CHANGELOG.md): what is in 0.1.0.

## License

[MIT](LICENSE).
