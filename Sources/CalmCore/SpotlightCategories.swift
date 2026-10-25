import Foundation

/// One entry of Spotlight's category list (`orderedItems` in the `com.apple.Spotlight` domain).
public struct SpotlightCategory: Equatable {
    public var name: String
    public var enabled: Bool
    public init(name: String, enabled: Bool) { self.name = name; self.enabled = enabled }
}

public enum SpotlightCategories {
    public static let applications = "APPLICATIONS"

    /// The categories macOS lists when the user never touched the settings (key absent).
    public static let defaults: [String] = [
        "APPLICATIONS", "MENU_EXPRESSION", "CONTACT", "MENU_CONVERSION", "MENU_DEFINITION", "DOCUMENTS",
        "EVENT_TODO", "DIRECTORIES", "FONTS", "IMAGES", "MESSAGES", "MOVIES", "MUSIC", "MENU_OTHER", "PDF",
        "PRESENTATIONS", "MENU_SPOTLIGHT_SUGGESTIONS", "SPREADSHEETS", "SYSTEM_PREFS", "TIPS", "BOOKMARKS", "SOURCE",
    ]

    /// Same order as `current` (or the defaults when the key is absent), everything off except applications.
    public static func appsOnly(from current: [SpotlightCategory]?) -> [SpotlightCategory] {
        let base = (current?.isEmpty == false ? current! : defaults.map { SpotlightCategory(name: $0, enabled: true) })
        var out = base.map { SpotlightCategory(name: $0.name, enabled: $0.name == applications) }
        if !out.contains(where: { $0.name == applications }) { out.insert(SpotlightCategory(name: applications, enabled: true), at: 0) }
        return out
    }

    /// Property-list form: [{ enabled = 1; name = "APPLICATIONS"; }, …]
    public static func plist(_ cats: [SpotlightCategory]) -> [[String: Any]] {
        return cats.map { ["enabled": $0.enabled, "name": $0.name] }
    }

    public static func parse(_ raw: Any?) -> [SpotlightCategory]? {
        guard let arr = raw as? [[String: Any]] else { return nil }
        let out = arr.compactMap { d -> SpotlightCategory? in
            guard let n = d["name"] as? String else { return nil }
            let e = (d["enabled"] as? Bool) ?? ((d["enabled"] as? Int).map { $0 != 0 } ?? true)
            return SpotlightCategory(name: n, enabled: e)
        }
        return out.count == arr.count ? out : nil
    }
}
