import Foundation
import Testing
@testable import EchnoKit

@Suite("Invite code")
struct InviteCodeTests {

    /// A valid code built from the required length rather than written out, so
    /// the expectation moves with the contract instead of having to be found
    /// and edited if the backend ever widens the code.
    private var validCode: String {
        String(repeating: "7", count: InviteCode.length)
    }

    @Test("A code of the required length is accepted")
    func acceptsTheRequiredLength() throws {
        let code = try #require(InviteCode(validCode))
        #expect(code.value == validCode)
    }

    @Test("A code of any other length is rejected")
    func rejectsOtherLengths() {
        for length in 0..<(InviteCode.length * 2) where length != InviteCode.length {
            #expect(
                InviteCode(String(repeating: "7", count: length)) == nil,
                "a \(length)-character code should not be accepted"
            )
        }
    }

    // Not pedantry about digits: the server parses the code with
    // `Integer.parseInt` and throws before it refunds the rate-limit attempt it
    // charged, so a letter in the field costs the user one of their few tries.
    // Catching it here spends nothing.
    @Test(
        "A code that is not all digits is rejected",
        arguments: ["1234A", "ABCDE", "12 34", "1234-", "１２３４５"]
    )
    func rejectsNonDigits(raw: String) {
        #expect(raw.count == InviteCode.length, "the sample should isolate the character, not the length")
        #expect(InviteCode(raw) == nil)
    }

    @Test("Whitespace around a pasted code is ignored")
    func trimsSurroundingWhitespace() throws {
        let code = try #require(InviteCode("  \(validCode)\n"))
        #expect(code.value == validCode)
    }

    @Test("Sanitizing keeps only digits and stops at the code length")
    func sanitizingKeepsDigitsUpToLength() {
        #expect(InviteCode.sanitize("12a3b4") == "1234")
        #expect(InviteCode.sanitize(String(repeating: "9", count: InviteCode.length + 3))
                == String(repeating: "9", count: InviteCode.length))
        #expect(InviteCode.sanitize("").isEmpty)
    }

    /// Ties the two together: what the field is allowed to contain at full
    /// length is exactly what the initializer accepts, so the Join button
    /// cannot enable on text the code type would reject.
    @Test("A sanitized entry of full length is always a valid code")
    func sanitizedFullLengthIsValid() throws {
        let typed = InviteCode.sanitize("8x8x8x8x8x8x8")
        #expect(typed.count == InviteCode.length)
        _ = try #require(InviteCode(typed))
    }
}
