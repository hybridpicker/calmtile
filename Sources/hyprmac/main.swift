import AppKit

if CommandLine.arguments.contains("--print-config") {
    print(Config.load().0.json())
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
let controller = Controller()
controller.start()
app.run()
