// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "calmtile",
    platforms: [.macOS(.v11)],
    targets: [
        // Pure layout/workspace logic (dwindle tree, workspaces, focus). No AppKit, fully testable.
        .target(name: "CalmCore"),
        // Self-test runner (XCTest is not guaranteed with Command Line Tools only).
        .target(name: "calmcore-selftest", dependencies: ["CalmCore"]),
        // The menu bar app: Accessibility windows, global hotkeys, config.
        .target(name: "calmtile", dependencies: ["CalmCore"]),
    ]
)
