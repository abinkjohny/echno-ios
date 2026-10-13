import Foundation

/// An organization invite code, validated before it is ever sent.
///
/// A plain `String` would do the job and this type exists anyway, because
/// redemption is **rate limited** and the limiter charges before it looks the
/// code up: `ProjectInviteCodeService.validateAndUseInviteCode` calls
/// `chargeAttempt`, then `parseCode`, and only refunds once the code is found
/// and accepted. `parseCode` is `Integer.parseInt`, so a code with a letter in
/// it throws between the two and the attempt is *not* given back. Text the
/// client can prove the server will reject therefore costs the user one of a
/// small number of tries, and the only way to not spend it is to not send it.
///
/// Holding the rule in a type rather than in the view keeps it testable and
/// keeps the only path to a request one that has been through it.
public struct InviteCode: Hashable, Sendable {

    /// How many characters a code has.
    ///
    /// Fixed by the contract: `InviteCodeValidationDto.code` declares
    /// `minLength` and `maxLength` of 5. The generator emits no length check
    /// for either, so the constraint has to live somewhere, and a named
    /// constant is what lets the tests and the text field agree with the
    /// schema instead of each repeating a 5.
    public static let length = 5

    /// The digits, with no surrounding whitespace.
    public let value: String

    /// Validates `raw` as a code, or fails.
    ///
    /// Surrounding whitespace is trimmed because a code usually arrives pasted
    /// out of a message, often with a space or a newline attached, and that is
    /// the user's clipboard rather than their mistake.
    ///
    /// - Returns: `nil` if `raw` is not exactly ``length`` ASCII digits.
    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == Self.length, trimmed.allSatisfy(Self.isDigit) else {
            return nil
        }
        self.value = trimmed
    }

    /// What a code field should hold after `raw` is typed into it: digits only,
    /// never longer than a code.
    ///
    /// Separate from ``init(_:)`` on purpose. This one is for the binding, so
    /// stray characters are dropped as they arrive and the field cannot hold
    /// something unsendable. The initializer stays strict, so a code assembled
    /// any other way is still checked rather than quietly cleaned up and sent.
    public static func sanitize(_ raw: String) -> String {
        String(raw.filter(isDigit).prefix(length))
    }

    /// ASCII digits only, not `Character.isNumber`.
    ///
    /// `isNumber` is true for the full-width forms and for other scripts'
    /// digits, and while Java's `parseInt` would accept several of them, what
    /// is sent then no longer looks like what was typed. Narrowing to ASCII
    /// keeps the request and the field the same five characters. The cost is
    /// that a full-width entry is rejected rather than translated; a number pad
    /// does not produce one, so the realistic way to see this is a paste.
    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}
