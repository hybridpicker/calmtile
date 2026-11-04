# Workspaces as real macOS desktops (`"useSpaces": true`)

Opt-in. Workspace N is a macOS desktop (Space) of the display: `⌘N` switches desktops, windows stay where
macOS puts them, nothing is parked in a corner and Mission Control shows a clean desktop per workspace.

## Numbers stay with their desktops

macOS moves the most recently used desktops to the front whenever Mission Control opens ("Automatically
rearrange Spaces based on most recent use", on by default), so "the Nth desktop" is a moving target and `⌘2`
would land somewhere else after every swipe up. calmtile gives a desktop the lowest free number when it first
sees it (Dock order at the first start) and remembers it in `~/.config/calmtile/desktops.json`; the menu bar
shows that number. Mission Control's own order and its "Desktop N" labels may differ. With the setting off,
the Dock's order is used as it is (a desktop dragged elsewhere in Mission Control then takes its new
position's number), like the system's `⌃N` shortcuts.

## A missing workspace is created when you go there

Hyprland semantics: `⌘N` on a desktop that does not exist opens Mission Control for about a second, presses
its "add desktop" button and clicks the new desktop, which gets number N whatever its position (`⌘5` with
desktops 1–3 creates only 5). macOS has no API for this short of disabling SIP; the Dock's Spaces bar is
driven through Accessibility, as yabai does. Verified on one display; with two displays the Spaces bar of
the display holding the active desktop is picked by position (not tested). `--remove-desktop N` removes
one by hand (see [development.md](development.md)).

With `"removeEmptyDesktops": true` a desktop you leave empty is removed, as Hyprland drops an empty
workspace: 1.2 s after the switch away (by key, swipe or Mission Control), when no window of any app lives
there any more (minimized and hidden ones count, a window shown on every desktop keeps every desktop),
calmtile removes it through the same Spaces bar. That opens Mission Control for about a second; a workspace
key pressed meanwhile runs right after. Off by default for that reason. `⌘N` brings the desktop back.

## Switching goes through the Dock

Setting the display's current Space directly (`CGSManagedDisplaySetCurrentSpace`, a private call any
process may make) does only half the job on macOS 26: the new desktop becomes current, but the one just left
stays shown (the window server then lists two "current" Spaces) and its windows keep being drawn over the
new desktop. Hiding a Space (`CGSHideSpaces`) is honoured for the Dock alone.

So `⌘N` presses the system shortcut "Switch to Desktop <position>" (`⌃<digit>`) for the Dock. That shortcut
is usually off in System Settings; calmtile switches it on in the window server
(`CGSSetSymbolicHotKeyEnabled`, the live state System Settings itself changes) for the 0.4 s of the
synthesized press and off again. Nothing is written to the preferences and your own `⌃<digit>` keeps its
meaning. The position is looked up in the Dock's current order at every press, so the automatic
rearranging does not matter. Beyond nine desktops the direct call is used. Verified live on macOS 26.5
(window server checked for 5 s after each switch: one shown Space, no return).

## Which desktop a window is on

Read from the window server (`CGSCopySpacesForWindows`), never from a window's presence in the
Accessibility window list: that list still shows the desktop just left for about 0.3 s after a switch.
Taking those windows as "here" used to tile them into the new workspace, resize them on their own desktop
and, when one of them was focused, pull macOS straight back to it.

- Right after a switch, a window of the new desktop that Accessibility has not listed yet keeps its tile;
  a window that is on the desktop but not drawn (minimized, its app hidden, ordered out) loses it.
- The window server's own report wobbles while the Dock animates a switch, so a window is re-homed only
  when two ticks agree and a single Space is shown. (A wrong re-homing made a window keep half of a
  desktop it had to itself: its supposed neighbour was on another desktop.)
- Trackpad swipes and Mission Control are followed: the active desktop becomes the current workspace, and
  a window dragged to another desktop changes workspace.

## Tiling on a desktop

- A new window is tiled from the "window created" notification, with the element the notification
  carries, instead of on the next tick: the frame is set while the window is still appearing. That cannot
  remove the flicker entirely, since the app draws its first frame itself; apps that restore their last
  frame open at their tile anyway.
- Windows always tile on their desktop, however small the tiles get (Hyprland): calmtile cannot move windows
  between Spaces (the private call has no effect on macOS 26.5, verified), so `minTileWidth`/`minTileHeight`
  only apply without `useSpaces`. Only a window whose own minimum size cannot sit beside its neighbours
  floats.
- Windows of a hidden app (`⌘H`) get no tile: Accessibility keeps listing them on their desktop although nothing
  is drawn, and as invisible neighbours they used to leave the visible windows half-sized. They are treated like
  minimized ones and tile again when the app is shown.
- Focus and the focused-window border never go to a window on another desktop: activating such a window
  makes macOS switch to its desktop.

## Moving a window to another desktop

`⌘⌥N` drags the window's title bar while pressing the system shortcut `⌃<position>`, enabled for that
moment the same way as for switching. The pointer is put back afterwards. This path is not tested live.

## Limits

- Only normal desktops of the display holding the active desktop count; full-screen app Spaces are skipped
  and workspaces 6–9 do not move to a second display in this mode.
- Desktops are created through Mission Control, which cannot be driven while the screen is locked.

# Parked workspaces and Mission Control (default mode)

All workspaces live on one macOS Space; inactive ones are parked in a corner. While Mission Control is open
(four-finger swipe up, `⌃↑`) calmtile moves every window to its layout position, so macOS shows a proper
overview instead of a pile in the corner. When it closes, windows are parked again and the workspace of the
window you picked becomes current. Measured: windows spread within about 0.1 s of opening, parked again
after closing.
