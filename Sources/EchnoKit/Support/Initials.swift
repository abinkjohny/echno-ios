import Foundation

/// One or two letters standing in for a picture.
///
/// Shared by ``User`` and ``Organization``, which both show an avatar and must
/// derive it identically — a person's initials and their organization's appear
/// side by side in the shell, and two rules would be visible as an
/// inconsistency long before anyone found the second implementation.
///
/// First and last word rather than the first two: middle names are common and
/// the last word is the part people recognise — "Ravi Kumar Sharma" reads as
/// RS, and "Tornotron Constructions Pvt Ltd" as TL rather than TC.
///
/// Returns empty when there is nothing to take. Callers show a glyph then;
/// punctuation in an avatar reads as a rendering fault rather than as "no name
/// on file".
///
/// Only words that *begin* with a letter count. Registration permits hyphens,
/// dots and apostrophes so "Mary-Jane O'Neill" validates, which also lets "---"
/// through — and `Character.isLetter` is true for a whole grapheme cluster, so
/// `കു` still qualifies.
public func initials(of name: String) -> String {
    let words = name
        .split(whereSeparator: \.isWhitespace)
        .filter { $0.first?.isLetter == true }
    guard let first = words.first else { return "" }
    let chosen = words.count > 1 ? [first, words[words.index(before: words.endIndex)]] : [first]
    return chosen.compactMap(\.first).map(String.init).joined().uppercased()
}
