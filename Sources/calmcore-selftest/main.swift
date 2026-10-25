import CoreGraphics
import Foundation
import CalmCore

var failures = 0
var checks = 0

func check(_ ok: Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !ok {
        failures += 1
        print("FAIL (line \(line)): \(what)")
    }
}

func frame(_ p: Placement?) -> CGRect? {
    if case .frame(let r)? = p { return r }
    return nil
}

func isHidden(_ p: Placement?) -> Bool {
    if case .hidden? = p { return true }
    return false
}

let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
func makeEngine() -> Engine {
    let e = Engine(monitors: [Monitor(id: 0, frame: screen)])
    e.gap = 8
    e.outerGap = 8
    return e
}

// 1. one window fills the screen minus the outer gap
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    check(frame(e.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "single window fills area")
}

// 2. dwindle: second window goes right, third splits the focused (right) one top/bottom
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.windowAppeared(3, floating: false)
    let p = e.plan()
    guard let f1 = frame(p[1]), let f2 = frame(p[2]), let f3 = frame(p[3]) else {
        check(false, "three frames exist")
        exit(1)
    }
    check(f1.minX == 8 && f2.minX > f1.maxX, "window 2 sits right of 1")
    check(f1.height == 1064, "window 1 keeps full height")
    check(f2.minY < f3.minY && f2.width == f3.width, "window 3 stacks under 2 (longer side of 2 is height)")
    check(!f1.intersects(f2) && !f2.intersects(f3) && !f1.intersects(f3), "no overlap")
    check(f2.minY - 8 >= 0 && f3.maxY <= 1072, "stays inside outer gap")
}

// 3. new window splits the FOCUSED one, not the last
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.setFocused(1)
    e.windowAppeared(3, floating: false)
    let p = e.plan()
    let f1 = frame(p[1])!, f3 = frame(p[3])!, f2 = frame(p[2])!
    check(f1.width == f3.width && f1.minY < f3.minY, "3 stacked below 1 after focusing 1")
    check(f2.minX > f1.maxX, "2 untouched on the right")
}

// 4. closing gives the space to the sibling
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.windowGone(2)
    check(frame(e.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "sibling takes over")
    check(e.focused == 1, "focus falls back to 1")
}

// 5. directional focus and swap
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.windowAppeared(3, floating: false)   // 1 | (2 over 3), focus on 3
    check(e.focus(.up) && e.focused == 2, "focus up from 3 -> 2")
    check(e.focus(.left) && e.focused == 1, "focus left from 2 -> 1")
    check(!e.focus(.left), "nothing left of 1")
    check(e.focus(.right), "focus right again")
    e.setFocused(1)
    let before = frame(e.plan()[1])!
    e.swap(.right)
    check(frame(e.plan()[1])! != before, "swap moved window 1")
    check(frame(e.plan()[2])! == before || frame(e.plan()[3])! == before, "neighbour took its place")
}

// 6. workspaces: switching hides, restoring shows again
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.switchWorkspace(2)
    check(isHidden(e.plan()[1]) && isHidden(e.plan()[2]), "ws1 windows hidden on ws2")
    e.windowAppeared(3, floating: false)
    check(frame(e.plan()[3]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "new window on ws2 fills screen")
    check(e.workspaceOf(3) == 2, "window 3 belongs to ws2")
    e.switchWorkspace(1)
    check(frame(e.plan()[1]) != nil && isHidden(e.plan()[3]), "back on ws1")
    check(e.focused == 2, "focus restored to last focused window of ws1")
    e.backAndForth()
    check(e.currentWorkspace == 2 && e.focused == 3, "back-and-forth returns to ws2")
}

// 7. move focused window to another workspace
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.moveFocused(toWorkspace: 3)
    check(e.workspaceOf(2) == 3, "2 moved to ws3")
    check(isHidden(e.plan()[2]), "2 hidden (ws3 not visible)")
    check(frame(e.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "1 grows back")
    check(e.focused == 1, "focus follows to remaining window")
}

// 8. fullscreen covers the monitor, toggling restores
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.toggleFullscreen()
    check(frame(e.plan()[2]) == screen, "fullscreen = whole monitor")
    e.toggleFullscreen()
    check(frame(e.plan()[2]) != screen, "fullscreen off")
}

// 9. floating windows leave the tree and return
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.toggleFloating()
    check(e.isFloating(2), "2 floating")
    check(frame(e.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "1 takes the whole area")
    check(frame(e.plan()[2]) != nil, "floating keeps a frame")
    e.toggleFloating()
    check(!e.isFloating(2) && frame(e.plan()[2])!.width < 1904, "2 tiled again")
}

// 10. two monitors: workspaces 6-9 live on the second one, both visible at once
do {
    let second = CGRect(x: 1920, y: 0, width: 1440, height: 900)
    let e = Engine(monitors: [Monitor(id: 0, frame: screen), Monitor(id: 1, frame: second)])
    e.windowAppeared(1, floating: false)
    e.switchWorkspace(6)
    e.windowAppeared(2, floating: false)
    let p = e.plan()
    check(frame(p[1]) != nil, "ws1 still visible on monitor 0")
    check(frame(p[2])!.minX >= 1920, "ws6 window on monitor 1")
    e.setMonitors([Monitor(id: 0, frame: screen)])
    check(frame(e.plan()[2])!.maxX <= 1920, "unplugging moves ws6 onto the remaining monitor")
}

// 11. resize moves the divider
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.setFocused(1)
    let w = frame(e.plan()[1])!.width
    e.resize(.right)
    check(frame(e.plan()[1])!.width > w, "divider moved right")
}

// 12. mouse: dragging a divider and dropping a window on another
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.setFocused(1)
    let w = frame(e.plan()[1])!.width
    e.resizeBy(dx: 100, dy: 0)
    check(abs(frame(e.plan()[1])!.width - (w + 100)) <= 2, "dx of 100 px moves the divider by 100 px")
    e.resizeBy(dx: 0, dy: 50)
    check(frame(e.plan()[1])!.height == 1064, "dy without a vertical split changes nothing")
    let a = frame(e.plan()[1])!
    let b = frame(e.plan()[2])!
    e.swapWindows(1, 2)
    check(frame(e.plan()[1])! == b && frame(e.plan()[2])! == a, "swapWindows exchanges the tiles")
}

// 13. activate switches to the workspace of the window
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.moveFocused(toWorkspace: 2)           // window 2 -> ws2
    check(e.windows(in: 1) == [1] && e.windows(in: 2) == [2], "windows listed per workspace")
    e.activate(2)
    check(e.currentWorkspace == 2 && e.focused == 2, "activate switches workspace and focuses")
    check(frame(e.plan()[2]) != nil && isHidden(e.plan()[1]), "activated window visible, other hidden")
    e.activate(1)
    check(e.currentWorkspace == 1 && e.focused == 1, "activate back")
}

// 14. launcher matching and themes
do {
    check(fuzzyScore("", "Safari") == 0, "empty query matches")
    check(fuzzyScore("sfr", "Safari") != nil, "subsequence matches")
    check(fuzzyScore("xyz", "Safari") == nil, "missing letters do not match")
    check(fuzzyScore("saf", "Safari")! > fuzzyScore("saf", "Microsoft Access Forms")!, "prefix beats scattered match")
    check(fuzzyScore("ff", "Final Fantasy")! > fuzzyScore("ff", "Offline")!, "word starts score higher")
    // Ranking over real application names: the best placement counts, and so do CamelCase word starts.
    let apps = ["TextEdit", "Microsoft Edge", "Google Chrome", "LibreMetronome", "Calculator", "Calendar",
                "Activity Monitor", "App Store", "Terminal", "Mail", "Maps", "Messages", "Music", "Safari",
                "System Settings", "Xcode", "Visual Studio Code", "Preview", "Photos", "Firefox Developer Edition",
                "Image Capture", "Logic Pro"]
    func top(_ q: String) -> String? {
        return apps.compactMap { a in fuzzyScore(q, a).map { (a, $0) } }.max { $0.1 < $1.1 }?.0
    }
    check(fuzzyScore("ed", "TextEdit")! > fuzzyScore("ed", "Microsoft Edge")!, "'ed' finds the Ed of TextEdit")
    check(top("ed") == "TextEdit", "'ed' ranks TextEdit first")
    check(top("lm") == "LibreMetronome", "'lm' takes the CamelCase start of Metronome")
    check(top("gc") == "Google Chrome", "acronym 'gc' keeps Google Chrome first")
    check(top("ss") == "System Settings", "acronym 'ss' beats the double s of Messages")
    check(top("vsc") == "Visual Studio Code", "three-word acronym")
    check(top("am") == "Activity Monitor", "'am' is Activity Monitor")
    check(top("term") == "Terminal", "prefix")
    check(top("xc") == "Xcode", "short prefix")
    check(top("safari") == "Safari", "whole name")
    check(fuzzyScore("cal", "Calendar")! > fuzzyScore("cal", "Image Capture") ?? Int.min, "prefix beats a scattered match")
    check(fuzzyScore("mail", "Mail")! > fuzzyScore("mail", "Mailchimp")!, "shorter text wins an equal match")
    check(fuzzyScore("tdx", "TextEdit") == nil, "order matters")
    check(Set(Theme.all.map { $0.name }).count == Theme.all.count, "theme names are unique")
    check(Theme.all.allSatisfy { [$0.background, $0.foreground, $0.accent].allSatisfy { $0.count == 7 && $0.hasPrefix("#") } }, "theme colours are #rrggbb")
    check(Theme.after(Theme.all.last!.name) == Theme.all[0], "theme-next wraps")
    check(Theme.named("Nord")?.name == "nord", "theme lookup ignores case")
}

// 15. scratchpad
do {
    let e = makeEngine()
    check(!e.toggleScratchpad(), "empty scratchpad toggles nothing")
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.setFocused(2)
    e.moveFocusedToScratchpad()
    check(isHidden(e.plan()[2]) && e.workspaceOf(2) == 0, "scratchpad window is hidden")
    check(frame(e.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "the other window takes the space")
    check(e.focused == 1, "focus returns to the remaining window")
    check(e.toggleScratchpad() && frame(e.plan()[2]) != nil && e.focused == 2, "toggle shows and focuses it")
    check(frame(e.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "tiles are not disturbed while shown")
    check(e.toggleScratchpad() && isHidden(e.plan()[2]) && e.focused == 1, "toggle hides it again")
    e.toggleScratchpad()
    e.moveFocusedToScratchpad()
    check(e.workspaceOf(2) == 1 && e.isFloating(2) && frame(e.plan()[2]) != nil, "a shown scratchpad window returns to the workspace")
    e.moveToScratchpad(1)
    e.windowGone(1)
    check(!e.toggleScratchpad(), "a closed scratchpad window is forgotten")
}

// minimum tile size: windows that would not fit float instead of being squeezed
do {
    let e = makeEngine()   // 1920x1080
    for id in 1...8 { e.windowAppeared(WindowID(id), floating: false) }
    let tiled = e.tiledFrames()
    check(tiled.values.allSatisfy { $0.width >= 420 && $0.height >= 280 }, "no tile below the minimum size")
    check(tiled.count == 4 && e.workspaceOf(8) == 2 && e.currentWorkspace == 2, "the overflow window opens on the next workspace")
    let f = makeEngine()
    f.windowAppeared(1, floating: false)
    f.windowAppeared(2, floating: false)
    f.floatTooBig(2, actual: CGSize(width: 900, height: 700))
    check(f.isFloating(2) && frame(f.plan()[2])?.size == CGSize(width: 900, height: 700), "a too-big window floats at its own size")
    check(frame(f.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "the other window gets the whole area back")
    let g = makeEngine()
    g.windowAppeared(1, floating: false)
    g.windowAppeared(2, floating: false)
    g.noteMinSize(1, want: CGSize(width: 944, height: 1064), got: CGSize(width: 1200, height: 1064))
    let g1 = frame(g.plan()[1])!, g2 = frame(g.plan()[2])!
    check(g1.width >= 1200 && g1.maxX <= g2.minX, "a window with a minimum width gets it and the neighbour shrinks")
    g.noteMinSize(2, want: g2.size, got: CGSize(width: 1200, height: g2.height))
    check(g.workspaceOf(2) == 2 && g.currentWorkspace == 2 && isHidden(g.plan()[1]) && frame(g.plan()[2]) != nil, "minimums that cannot both fit send one window to the next workspace")
}

// relocate: a window moved to another desktop by macOS changes workspace without switching
do {
    let e = makeEngine()
    e.allowOverflow = false
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.relocate(2, to: 3)
    check(e.workspaceOf(2) == 3 && e.currentWorkspace == 1, "relocate re-homes without switching")
    check(frame(e.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "the remaining window takes the area")
    let f = makeEngine()
    f.allowOverflow = false
    for id in 1...8 { f.windowAppeared(WindowID(id), floating: false) }
    check(f.currentWorkspace == 1 && f.windows(in: 1).count == 8, "no overflow to another workspace when disabled")
    let tiles = Array(f.tiledFrames().values)
    check(tiles.count == 8, "without overflow every window tiles, however small (Hyprland)")
    check(tiles.allSatisfy { $0.width > 0 && $0.height > 0 }, "tiles keep a size")
    check(!tiles.enumerated().contains { i, a in tiles.dropFirst(i + 1).contains { a.intersects($0) } }, "tiles never overlap")
    // A window that opened on another desktop (window server says so) joins that workspace without becoming focused.
    let g = makeEngine()
    g.allowOverflow = false
    g.windowAppeared(1, floating: false)
    g.windowAppeared(2, floating: false, workspace: 3)
    check(g.workspaceOf(2) == 3 && g.currentWorkspace == 1 && g.focused == 1, "a window of another desktop is homed there, focus stays")
    check(frame(g.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "the current workspace is not disturbed")
    g.switchWorkspace(3)
    check(g.focused == 2 && frame(g.plan()[2]) != nil, "switching there focuses it")
}

// resize smart grows/shrinks the focused window along its split
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    e.setFocused(1)
    let w0 = frame(e.plan()[1])!.width
    e.resizeSmart(grow: true)
    check(frame(e.plan()[1])!.width > w0, "smart grow widens the first window")
    e.setFocused(2)
    let w1 = frame(e.plan()[2])!.width
    e.resizeSmart(grow: false)
    check(frame(e.plan()[2])!.width < w1, "smart shrink narrows the second window")
}

// monitors: workspaces 6-9 fall back to the main display, hot-plug moves them, workspace can move by hand
do {
    let m0 = Monitor(id: 0, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    let m1 = Monitor(id: 1, frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
    let e = Engine(monitors: [m0])
    e.switchWorkspace(7)
    e.windowAppeared(1, floating: false)
    check(frame(e.plan()[1])!.maxX <= 1000, "workspace 7 falls back to the main display")
    e.setMonitors([m0, m1])
    check(frame(e.plan()[1])!.minX >= 1000, "workspace 7 moves to the second display when it appears")
    e.setMonitors([m0])
    check(frame(e.plan()[1])!.maxX <= 1000, "unplugging returns it to the main display")
    e.setMonitors([m0, m1])
    e.moveWorkspaceToNextMonitor()
    check(frame(e.plan()[1])!.minX < 1000, "move-workspace-to-monitor wraps to the first display")
    e.setMonitors([m0])
    e.setMonitors([m0, m1])
    check(frame(e.plan()[1])!.minX < 1000, "the manual monitor choice survives hot-plug")
    let f = Engine(monitors: [m0, m1])
    f.switchWorkspace(6)
    f.windowAppeared(9, floating: true, frame: CGRect(x: 1200, y: 100, width: 400, height: 300))
    f.setMonitors([m0])
    check(frame(f.plan()[9])!.intersects(m0.frame), "a floating window of an unplugged display is brought back")
}

// Spotlight categories
do {
    let fresh = SpotlightCategories.appsOnly(from: nil)
    check(fresh.filter { $0.enabled }.map { $0.name } == ["APPLICATIONS"], "apps-only enables only applications")
    check(fresh.count == SpotlightCategories.defaults.count, "apps-only from absent key lists all defaults")
    let custom = [SpotlightCategory(name: "DOCUMENTS", enabled: true), SpotlightCategory(name: "APPLICATIONS", enabled: false)]
    let r = SpotlightCategories.appsOnly(from: custom)
    check(r.map { $0.name } == ["DOCUMENTS", "APPLICATIONS"] && r[1].enabled && !r[0].enabled, "order kept, applications forced on")
    check(SpotlightCategories.appsOnly(from: [SpotlightCategory(name: "PDF", enabled: true)]).first?.name == "APPLICATIONS", "applications added when missing")
    check(SpotlightCategories.parse(SpotlightCategories.plist(custom)) == custom, "plist round trip")
}

if failures == 0 {
    print("OK - \(checks) checks passed")
} else {
    print("\(failures) of \(checks) checks failed")
    exit(1)
}
