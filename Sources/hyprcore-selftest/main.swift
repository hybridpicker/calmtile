import CoreGraphics
import Foundation
import HyprCore

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

if failures == 0 {
    print("OK - \(checks) checks passed")
} else {
    print("\(failures) of \(checks) checks failed")
    exit(1)
}
