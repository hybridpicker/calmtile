/// Colours as #rrggbb. `accent` is the focused-window border and the launcher highlight.
public struct Theme: Equatable {
    public let name: String
    public let title: String
    public let background: String
    public let foreground: String
    public let accent: String

    public static let all: [Theme] = [
        Theme(name: "catppuccin", title: "Catppuccin", background: "#1e1e2e", foreground: "#cdd6f4", accent: "#89b4fa"),
        Theme(name: "tokyo-night", title: "Tokyo Night", background: "#1a1b26", foreground: "#c0caf5", accent: "#7aa2f7"),
        Theme(name: "gruvbox", title: "Gruvbox", background: "#282828", foreground: "#ebdbb2", accent: "#fabd2f"),
        Theme(name: "nord", title: "Nord", background: "#2e3440", foreground: "#d8dee9", accent: "#88c0d0"),
        Theme(name: "rose-pine", title: "Ros\u{e9} Pine", background: "#191724", foreground: "#e0def4", accent: "#c4a7e7"),
        Theme(name: "everforest", title: "Everforest", background: "#2d353b", foreground: "#d3c6aa", accent: "#a7c080"),
        Theme(name: "kanagawa", title: "Kanagawa", background: "#1f1f28", foreground: "#dcd7ba", accent: "#7e9cd8"),
        Theme(name: "catppuccin-latte", title: "Catppuccin Latte", background: "#eff1f5", foreground: "#4c4f69", accent: "#1e66f5"),
    ]

    public static func named(_ name: String) -> Theme? {
        return all.first { $0.name == name.lowercased() }
    }

    public static func after(_ name: String) -> Theme {
        guard let i = all.firstIndex(where: { $0.name == name }) else { return all[0] }
        return all[(i + 1) % all.count]
    }
}
