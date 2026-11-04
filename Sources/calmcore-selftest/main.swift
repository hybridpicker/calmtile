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
    // Usage only breaks ties: it never lifts a worse match.
    let often = LauncherRank(score: 40, uses: 9, kind: 2, title: "Microsoft Edge")
    let rare = LauncherRank(score: 47, uses: 0, kind: 2, title: "TextEdit")
    check(ranksBefore(rare, often), "a better match beats a more used app")
    check(ranksBefore(LauncherRank(score: 40, uses: 3, kind: 2, title: "Maps"), LauncherRank(score: 40, uses: 1, kind: 2, title: "Mail")),
          "between equal matches the more used app comes first")
    check(ranksBefore(LauncherRank(score: 0, uses: 0, kind: 2, title: "calendar"), LauncherRank(score: 0, uses: 0, kind: 2, title: "Maps")),
          "without usage the title decides, ignoring case")
    check(ranksBefore(LauncherRank(score: 0, uses: 0, kind: 0, title: "z"), LauncherRank(score: 0, uses: 0, kind: 2, title: "a")),
          "windows before applications at equal score")
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

// pixel-exact tiles: random insert/remove/resize/flip sequences on several monitors, fractional ones too
do {
    var seed: UInt64 = 0x5eed
    func rnd(_ n: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 33) % UInt64(n))
    }
    func integral(_ r: CGRect) -> Bool {
        return [r.minX, r.minY, r.width, r.height].allSatisfy { $0 == $0.rounded() }
    }
    func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let w = min(a.maxX, b.maxX) - max(a.minX, b.minX), h = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return w > 0 && h > 0 ? w * h : 0
    }
    let areas = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 64.5, y: 24, width: 1375.5, height: 875.25),
                 CGRect(x: 1440, y: -200, width: 2560, height: 1415), CGRect(x: 0, y: 0, width: 1001, height: 777)]
    for area in areas {
        for (gap, outer) in [(CGFloat(0), CGFloat(0)), (8, 8), (7.5, 3.25)] {
            let e = Engine(monitors: [Monitor(id: 0, frame: area)])
            e.gap = gap
            e.outerGap = outer
            e.allowOverflow = false
            e.minTile = .zero
            let inner = Monitor.aligned(area.insetBy(dx: outer, dy: outer))
            var ids = [WindowID](), next: WindowID = 1
            var notIntegral = 0, overlapping = 0, outside = 0, unfilled = 0, noNeighbour = 0
            for _ in 0..<300 {
                let r = rnd(10)
                if r < 4 || ids.isEmpty {
                    if ids.count < 12 { e.windowAppeared(next, floating: false); ids.append(next); next += 1 }
                } else if r < 6 {
                    let i = rnd(ids.count)
                    e.windowGone(ids[i])
                    ids.remove(at: i)
                } else if r < 8 {
                    e.setFocused(ids[rnd(ids.count)])
                    e.resize([Direction.left, .right, .up, .down][rnd(4)])
                } else {
                    e.setFocused(ids[rnd(ids.count)])
                    e.toggleSplit()
                }
                let tiles = e.tiledFrames()
                let list = Array(tiles.values)
                notIntegral += list.filter { !integral($0) }.count
                outside += list.filter { !inner.contains($0) }.count
                for i in 0..<list.count { for j in (i + 1)..<list.count where overlap(list[i], list[j]) > 0 { overlapping += 1 } }
                guard gap == 0, !list.isEmpty else { continue }
                if list.reduce(0, { $0 + $1.width * $1.height }) != inner.width * inner.height { unfilled += 1 }
                for (id, f) in tiles {
                    for (d, inside) in [(Direction.left, f.minX > inner.minX), (.right, f.maxX < inner.maxX),
                                        (.up, f.minY > inner.minY), (.down, f.maxY < inner.maxY)] where inside {
                        if Engine.neighbor(of: id, in: tiles, direction: d) == nil { noNeighbour += 1 }
                    }
                }
            }
            let what = "\(Int(area.width))x\(Int(area.height)) gap \(gap)/\(outer)"
            check(notIntegral == 0, "\(what): every tile is on whole points (\(notIntegral) not)")
            check(overlapping == 0, "\(what): tiles never overlap (\(overlapping) pairs)")
            check(outside == 0, "\(what): tiles stay inside the area (\(outside) outside)")
            check(unfilled == 0, "\(what): with no gap the tiles fill the area (\(unfilled) steps not)")
            check(noNeighbour == 0, "\(what): with no gap every inner edge has a neighbour (\(noNeighbour) missing)")
        }
    }
    check(Monitor.aligned(CGRect(x: 64.5, y: 24.25, width: 1375.5, height: 875.5)) == CGRect(x: 65, y: 25, width: 1375, height: 874),
          "a fractional area shrinks to whole points")
}

// fixed-size windows (tileFixedApps): a tile of their own size, the neighbours get the rest
do {
    let e = makeEngine()   // area 1904 x 1064 at (8, 8), gap 8
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false, fixedSize: CGSize(width: 410, height: 880))
    let f1 = frame(e.plan()[1]), f2 = frame(e.plan()[2])
    check(f2?.size == CGSize(width: 410, height: 880), "a fixed-size window's tile is its own size")
    check(f2?.minY == 8 && f2?.maxX == 1912, "it sits at the top-left corner of the space it was given")
    check(f1?.width == 1904 - 8 - 410 && f1?.height == 1064, "the neighbour takes all the width it cannot use")
    e.setFocused(1)
    e.windowAppeared(3, floating: false)   // splits window 1
    let p = e.plan()
    check(frame(p[2])?.size == CGSize(width: 410, height: 880), "it keeps its size when its neighbour splits")
    let tiles = [1, 3, 2].compactMap { frame(p[WindowID($0)]) }
    check(tiles.count == 3 && !tiles[0].intersects(tiles[1]) && !tiles[0].intersects(tiles[2]) && !tiles[1].intersects(tiles[2]),
          "no overlap with a fixed-size window")
    e.setFixedSize(2, CGSize(width: 880, height: 410))   // the device rotated
    check(frame(e.plan()[2])?.size == CGSize(width: 880, height: 410), "the tile follows a new size")
    e.windowGone(2)
    check(max(frame(e.plan()[1])?.maxX ?? 0, frame(e.plan()[3])?.maxX ?? 0) == 1912, "after it closes the others share the full width again")
    check(e.fixedSize(of: 2) == nil, "its size is forgotten when it closes")
    e.windowAppeared(4, floating: true, fixedSize: CGSize(width: 300, height: 300))
    check(e.fixedSize(of: 4) == nil, "a floating window keeps no fixed tile size")
}

// a new window next to a focused fixed-size one goes where the free space is, not into the strip under it
do {
    let e = Engine(monitors: [Monitor(id: 0, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))])
    e.gap = 0
    e.outerGap = 0
    e.allowOverflow = false
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false, fixedSize: CGSize(width: 410, height: 880))   // focused now
    e.windowAppeared(3, floating: false)
    let p = e.plan()
    let f2 = frame(p[2]), f3 = frame(p[3])
    check(f2?.size == CGSize(width: 410, height: 880), "the fixed-size window keeps its size")
    check((f3?.height ?? 0) == 900 && (f3?.width ?? 0) >= 300, "the new window gets the width beside it, full height")
    // a minimum that cannot fit: the window floats where the app had put it, not at the size it was squeezed to
    e.noteMinSize(3, want: f3?.size ?? .zero, got: CGSize(width: 2000, height: 900), natural: CGRect(x: 100, y: 50, width: 656, height: 422))
    check(e.isFloating(3) && frame(e.plan()[3]) == CGRect(x: 100, y: 50, width: 656, height: 422),
          "a window that has to float goes back to its own frame")
}

// title rules, float frames and the Mission Control overview
do {
    let e = makeEngine()
    e.windowAppeared(1, floating: false)
    e.windowAppeared(2, floating: false)
    let playlist = CGRect(x: 100, y: 100, width: 300, height: 400)
    e.makeFloating(2, frame: playlist)
    check(e.isFloating(2) && frame(e.plan()[2]) == playlist, "a title rule floats a tiled window at the frame given")
    check(frame(e.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "the remaining window takes the workspace")
    let moved = CGRect(x: 500, y: 200, width: 300, height: 400)
    e.noteFloatFrame(2, moved)
    e.switchWorkspace(2)
    e.switchWorkspace(1)
    check(frame(e.plan()[2]) == moved, "a floating window comes back where the user left it")
    e.noteFloatFrame(1, moved)
    check(frame(e.plan()[1]) == CGRect(x: 8, y: 8, width: 1904, height: 1064), "a tiled window ignores a float frame")
    e.windowAppeared(3, floating: false, workspace: 2)
    let o = e.overviewPlan()
    check(o[1] != nil && o[2] == moved && o[3] == CGRect(x: 8, y: 8, width: 1904, height: 1064),
          "the overview lays out every workspace, the hidden one included")
    e.windowAppeared(4, floating: false)
    e.setFocused(4)
    e.toggleFullscreen()
    check(e.currentFullscreen == 4, "fullscreen is reported for the current workspace")
}

// micro-benchmark: 200 windows in and out with a plan every ten, so regressions in the core show up
do {
    var best = Double.infinity
    for _ in 0..<3 {
        let e = Engine(monitors: [Monitor(id: 0, frame: CGRect(x: 0, y: 0, width: 2560, height: 1600))])
        e.allowOverflow = false
        e.minTile = .zero
        let t0 = Date()
        for id in WindowID(1)...200 {
            e.windowAppeared(id, floating: false)
            if id % 10 == 0 { _ = e.plan() }
        }
        for id in WindowID(1)...200 {
            e.windowGone(id)
            if id % 10 == 0 { _ = e.plan() }
        }
        best = min(best, Date().timeIntervalSince(t0))
    }
    print(String(format: "benchmark: 200 windows in and out with plans: %.1f ms", best * 1000))
    check(best < 0.05, "200 windows in and out with plans take under 50 ms")
}

if failures == 0 {
    print("OK - \(checks) checks passed")
} else {
    print("\(failures) of \(checks) checks failed")
    exit(1)
}
