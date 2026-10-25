# First steps

Ten minutes from install to a workspace that arranges itself. Each step says what you should see, and what
it means when you do not. The full reference is the [manual](manual.md).

## 0. Before you start

calmtile takes `⌘1…9`, `⌘Space`, `⌘Return`, `⇧⌘Return` and the `⌥`/`⌃⌥` keys listed in the manual. Quit any
other tiling or hotkey tool first (AeroSpace, yabai, Karabiner bindings on the same keys): only one tool can
own a key. Everything calmtile changes can be undone; the manual's section 11 lists how.

## 1. Install (2 minutes)

```bash
git clone https://github.com/hybridpicker/calmtile.git
cd calmtile
scripts/build.sh install
open ~/Applications/calmtile.app
```

You should see: `== self-test`, `OK - … checks passed`, `== app`, `installed ~/Applications/calmtile.app`,
then an alert from calmtile asking for Accessibility.

If you see `no signing identity found` instead of a quiet signature line, the build still works; macOS
will just ask for the Accessibility permission again after every rebuild.

## 2. Permissions (1 minute)

Open System Settings → Privacy & Security → **Accessibility**, switch calmtile on. If macOS also shows a
prompt for **Input Monitoring**, allow that too. Start calmtile again.

You should see `▦ 1` in the menu bar. Click it: a menu with "Workspace 1 ← here", the windows on it, and
the commands at the bottom.

If the alert comes back, the permission did not apply: check that the entry in the Accessibility list is
`calmtile` from `~/Applications` and switched on, remove and add it if in doubt, then start again.

## 3. Watch two windows tile (1 minute)

Press `⌘Return`. A Terminal window opens and fills the screen minus the gaps. Press `⌘Return` again: the
first window moves to the left half, the new one takes the right half, with a coloured outline around the
focused one that fades after a moment.

Open a third app of your choice. It splits the focused window: if that window was wider than tall, side by
side; if taller, stacked. Close one window (`⌃⌥W`): the window it was split from takes the space back.

If a window appears and stays at its own size without an outline: it is not a standard window (a dialog or
a panel) or its app refuses to be resized; see the manual, section 7. If nothing moves at all: tiling is
paused (`▦ ⏸`, press `⌃⌥P`) or the permission is missing.

## 4. Workspaces (2 minutes)

Press `⌘2`. The windows disappear, the menu bar shows `▦ 2`: an empty workspace. Press `⌘Return` here and
the Terminal opens alone, full size. Press `⌘1` and your first windows are back exactly as they were, `⌥Tab`
and you are on 2 again.

Now send a window across: on workspace 1 focus a window and press `⌘⌥2`. It leaves; the remaining windows
grow. `⌘2` shows it next to the Terminal there.

By default workspaces are *parked*: the windows you do not see are moved just off the bottom-right corner,
not to another macOS desktop, so switching is instant and Mission Control still works (it lays the parked
windows out while it is open). If you would rather have real macOS desktops per workspace, that is the
`useSpaces` option, step 8.

## 5. Move the focus without the mouse (1 minute)

With two or three windows on a workspace press `⌘←`, `⌘→`, `⌘↑`, `⌘↓`. The outline jumps to the neighbour in
that direction. `⌃⌥⇧→` swaps the focused window with its right neighbour; `⌃⌥⌘→` moves the divider to the
right; `⌃⌥S` turns a side-by-side split into a stacked one and back.

If `⌘←` moves the text cursor instead of the focus: there is no window to the left, and calmtile hands the
key to the app on purpose.

## 6. The launcher (1 minute)

Press `⌘Space`. A search field appears; type the first letters of an app and press `Return`: the app
starts and its window tiles on this workspace. An app that already runs is only activated; its windows stay
on their workspace, so use `⌃⌥Space` and pick the window to jump there. Spotlight stays closed while
calmtile runs.

Press `⌃⌥Space`: the same field, now with your open windows ("App – title", `Return` jumps to the window
and its workspace), applications and calmtile actions such as "Go to workspace 4" or "Theme: Nord". `Esc`
closes it.

If the field appears but your typing lands in the window behind it: macOS sometimes grants calmtile the
foreground late; press `Esc` and `⌘Space` again. If Spotlight opens instead: another tool took `⌘Space`
first, quit it.

## 7. Make it yours (2 minutes)

Create `~/.config/calmtile/config.json`:

```json
{
  "gap": 8,
  "outerGap": 8,
  "theme": "nord",
  "passthroughApps": ["com.dashlane.dashlanephonefinal"]
}
```

Press `⌃⌥R`. The gaps change at once; the border and the launcher take the theme (`⌃⌥⇧Space` cycles the
others). Add an app to `passthroughApps` when it needs `⌘1…9` for itself, such as a terminal with tabs; while
it is frontmost calmtile intercepts nothing. `scratchpadApp`, `bindings` and the rest are in the manual.

If the alert "unknown key combination" or "unknown action" appears, the config has a typo; `⌃⌥R` again after
fixing it.

## 8. Optional: real macOS desktops

Add `"useSpaces": true` to the config and press `⌃⌥R`. From now on `⌘N` switches to the Nth desktop, creating
it if needed, and every desktop keeps its own tiling; swipes and Mission Control keep working. Try `⌘3` with
only two desktops: Mission Control opens for a second, a desktop appears, and you are on it.

What changes: windows cannot be moved between desktops by calmtile directly (`⌘⌥N` drags the window with
the system shortcut instead), and workspaces 6–9 stay on the main display. [desktops.md](desktops.md) has
the details. To go back, remove the line and press `⌃⌥R`; the desktops you created stay until you remove
them in Mission Control.

## 9. If it is not for you

`⌃⌥P` pauses everything, the menu item **Quit calmtile** ends it and restores the Spotlight setting if it
was changed. Remove the app from `~/Applications` and the permissions from System Settings, and
`~/.config/calmtile` if you want a clean slate.
