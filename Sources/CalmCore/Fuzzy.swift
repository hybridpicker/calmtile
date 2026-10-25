/// Subsequence match for the launcher: every query character must appear in order.
/// Higher is better; nil means no match.
public func fuzzyScore(_ query: String, _ text: String) -> Int? {
    let q = Array(query.lowercased())
    let t = Array(text.lowercased())
    if q.isEmpty { return 0 }
    var qi = 0
    var score = 0
    var last = -2
    for (i, c) in t.enumerated() where qi < q.count && c == q[qi] {
        score += 10
        if i == last + 1 { score += 15 }                                   // consecutive
        if i == 0 || t[i - 1] == " " || t[i - 1] == "-" { score += 20 }    // start of a word
        last = i
        qi += 1
    }
    return qi == q.count ? score - t.count : nil
}
