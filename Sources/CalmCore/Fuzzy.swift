/// Subsequence match for the launcher: every query character must appear in order.
/// Higher is better; nil means no match.
///
/// Each matched character scores 10, plus 15 when it directly follows the previous match and 20 at the start of a
/// word; shorter texts win ties. A word starts at the beginning, after a space, `-`, `_` or `.`, and at an upper-case
/// letter that follows a lower-case one in the original text ("Edit" in "TextEdit", "Metronome" in
/// "LibreMetronome"). The best placement of the query is taken, not the first occurrence of each character: "ed"
/// finds the "Ed" in "TextEdit" rather than its first "e" and last "d".
public func fuzzyScore(_ query: String, _ text: String) -> Int? {
    let q = Array(query.lowercased())
    if q.isEmpty { return 0 }
    let orig = Array(text)
    let t = Array(text.lowercased())
    // Lower-casing keeps the character count for everything a launcher shows; fall back to plain starts if not.
    let sameShape = orig.count == t.count
    let n = t.count
    guard q.count <= n else { return nil }

    var start = [Bool](repeating: false, count: n)
    for i in 0..<n {
        if i == 0 { start[i] = true; continue }
        let p = t[i - 1]
        if p == " " || p == "-" || p == "_" || p == "." { start[i] = true; continue }
        if sameShape, orig[i].isUppercase, orig[i - 1].isLowercase { start[i] = true }
    }

    // best[i]: highest score with the query so far matched and its last character at text position i.
    let none = Int.min / 2
    var prev = [Int](repeating: none, count: n)
    for i in 0..<n where t[i] == q[0] { prev[i] = 10 + (start[i] ? 20 : 0) }
    for qi in 1..<q.count {
        var cur = [Int](repeating: none, count: n)
        var bestBefore = none   // max of prev[0...i-2]
        for i in 0..<n {
            if i >= 2 { bestBefore = max(bestBefore, prev[i - 2]) }
            guard t[i] == q[qi], i >= 1 else { continue }
            let gap = bestBefore
            let adjacent = prev[i - 1] == none ? none : prev[i - 1] + 15
            let from = max(gap, adjacent)
            if from == none { continue }
            cur[i] = from + 10 + (start[i] ? 20 : 0)
        }
        prev = cur
    }
    let best = prev.max() ?? none
    return best == none ? nil : best - n
}

/// One launcher entry as the ordering sees it.
public struct LauncherRank {
    public var score: Int
    public var uses: Int
    public var kind: Int
    public var title: String
    public init(score: Int, uses: Int, kind: Int, title: String) {
        self.score = score
        self.uses = uses
        self.kind = kind
        self.title = title
    }
}

/// Launcher order: the better match first; between equal matches windows before actions before applications (as
/// before), then the entry launched more often from the launcher, then by title.
public func ranksBefore(_ a: LauncherRank, _ b: LauncherRank) -> Bool {
    if a.score != b.score { return a.score > b.score }
    if a.kind != b.kind { return a.kind < b.kind }
    if a.uses != b.uses { return a.uses > b.uses }
    return a.title.lowercased() < b.title.lowercased()
}
