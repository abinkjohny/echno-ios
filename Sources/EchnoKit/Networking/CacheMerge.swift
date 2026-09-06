import Foundation

/// Merges a partial mutation response onto a cached value without dropping its
/// nested collections.
///
/// ## Why this exists
///
/// The backend returns three different shapes from mutation endpoints, and the
/// safe cache action differs per shape:
///
/// | Response | Contains | Store action |
/// | --- | --- | --- |
/// | `<Domain>Dto` (full) | id + scalars + nested arrays | replace the cached value |
/// | `<Domain>SimpleDto` (partial) | id + scalars only | **merge, preserving nested** |
/// | `ApiResponse` (ack) | nothing structured | refetch the affected keys |
///
/// Replacing a cached value with a `SimpleDto` silently blanks its nested
/// arrays — that shipped twice on web (vanishing attachments, add-member
/// rollback) before the rule was written down.
///
/// ## Why it is a protocol and not a generic function
///
/// A structural merge needs runtime reflection over field names, which is the
/// wrong tool here. Expressing it per type instead means each domain type with a
/// `SimpleDto` counterpart writes `merging(_:)` once, and the compiler — not a
/// convention — is what guarantees no nested field is dropped.
public protocol NestedMergeable: Sendable {

    /// The partial shape the backend returns from a `*SimpleDto` mutation.
    associatedtype Partial: Sendable

    /// Returns `self` with `partial`'s scalars applied and every nested
    /// array or object left intact.
    func merging(_ partial: Partial) -> Self
}

extension NestedMergeable {

    /// Merges `partial` onto an optional cached value.
    ///
    /// Returns `nil` when nothing was cached — the caller should refetch
    /// rather than fabricate an entry from a partial payload.
    public static func merge(_ cached: Self?, with partial: Partial) -> Self? {
        cached?.merging(partial)
    }
}
