import Foundation

/// The name of an application in the user's language, read from its own bundle; nil when it has none, and the file
/// name stands then.
///
/// FileManager.displayName, URLResourceValues.localizedName and NSRunningApplication.localizedName can't give this:
/// they follow the languages of the calling program, and calmtile only has English, so they answer "Calendar" on a
/// German system. Listing more languages in calmtile's Info.plist would also translate localizedName, which `open`
/// bindings and `scratchpadApp` compare with.
///
/// Apple's own apps keep their names in Contents/Resources/InfoPlist.loctable (one table per language), others in
/// <language>.lproj/InfoPlist.strings. A language the user did not ask for is not used: an app translated only into
/// French keeps its file name on a German system.
public func localizedAppName(at app: URL, preferredLanguages: [String]) -> String? {
    let resources = app.appendingPathComponent("Contents/Resources")
    if let name = nameInLocTable(resources, preferredLanguages) { return name }
    return nameInLprojStrings(resources, preferredLanguages)
}

private func nameInLocTable(_ resources: URL, _ preferred: [String]) -> String? {
    guard let data = FileManager.default.contents(atPath: resources.appendingPathComponent("InfoPlist.loctable").path),
          let table = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
    // Not every top-level entry is a language ("LocProvenance" is not), and not every language names the app.
    var names = [String: String]()
    for (language, entry) in table {
        if let strings = entry as? [String: Any], let name = appName(in: strings) { names[language] = name }
    }
    return bestLanguage(Array(names.keys), preferred).flatMap { names[$0] }
}

private func nameInLprojStrings(_ resources: URL, _ preferred: [String]) -> String? {
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? []
    let languages = entries.filter { $0.hasSuffix(".lproj") && $0 != "Base.lproj" }.map { String($0.dropLast(6)) }
    guard let language = bestLanguage(languages, preferred) else { return nil }
    let file = resources.appendingPathComponent("\(language).lproj/InfoPlist.strings").path
    return (NSDictionary(contentsOfFile: file) as? [String: Any]).flatMap(appName)
}

private func appName(in strings: [String: Any]) -> String? {
    for key in ["CFBundleDisplayName", "CFBundleName"] {
        // Apple's names carry soft hyphens for line breaking ("System\u{AD}einstellungen"). They are invisible and
        // would count as a gap in the fuzzy match, in the middle of what the user is typing.
        let name = (strings[key] as? String)?.replacingOccurrences(of: "\u{AD}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = name, !name.isEmpty { return name }
    }
    return nil
}

private func bestLanguage(_ available: [String], _ preferred: [String]) -> String? {
    guard let best = Bundle.preferredLocalizations(from: available, forPreferences: preferred).first else { return nil }
    // preferredLocalizations falls back to something from the list when nothing fits.
    func base(_ language: String) -> Substring {
        return language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? ""
    }
    return preferred.contains { base($0).lowercased() == base(best).lowercased() } ? best : nil
}
