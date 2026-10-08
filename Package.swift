// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "hyprmac",
    platforms: [.macOS(.v11)],
    targets: [
        // Pure layout/workspace logic (dwindle tree, workspaces, focus). No AppKit, fully testable.
        .target(name: "HyprCore"),
        // Self-test runner (XCTest is not guaranteed with Command Line Tools only).
        .target(name: "hyprcore-selftest", dependencies: ["HyprCore"]),
        // The menu bar app: Accessibility windows, global hotkeys, config.
        .target(name: "hyprmac", dependencies: ["HyprCore"]),
    ]
)
