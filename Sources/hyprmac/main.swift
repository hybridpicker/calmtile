import AppKit

if CommandLine.arguments.contains("--print-config") {
    print(Config.load().0.json())
    exit(0)
}

if CommandLine.arguments.contains("--dump-windows") {
    print(Windows.dump())
    exit(0)
}

if CommandLine.arguments.contains("--restore-spotlight") {
    SpotlightMode.restore()
    exit(0)
}

if CommandLine.arguments.contains("--apply-spotlight") {   // manual test of the apps-only switch
    SpotlightMode.enableAppsOnly()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
let controller = Controller()
controller.start()
app.run()
