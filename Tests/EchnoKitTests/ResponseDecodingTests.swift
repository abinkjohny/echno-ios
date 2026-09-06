import Foundation
import Testing
@testable import EchnoKit

@Suite("Response envelope decoding")
struct APIResponseTests {

    private struct Payload: Codable, Sendable, Equatable {
        let id: Int
        let name: String
    }

    @Test("A full envelope decodes every field")
    func fullEnvelope() throws {
        let json = Data(#"{"data":{"id":7,"name":"Site A"},"message":"ok","success":true}"#.utf8)
        let response = try JSONDecoder.echno.decode(APIResponse<Payload>.self, from: json)
        #expect(response.data == Payload(id: 7, name: "Site A"))
        #expect(response.message == "ok")
        #expect(response.success)
    }

    @Test("`success` defaults to true when the backend omits it")
    func successDefaultsTrue() throws {
        // Several endpoints return only `data`. Defaulting to false would make
        // every one of them look like a failure to the caller.
        let json = Data(#"{"data":{"id":1,"name":"A"}}"#.utf8)
        let response = try JSONDecoder.echno.decode(APIResponse<Payload>.self, from: json)
        #expect(response.success)
        #expect(response.message == nil)
    }

    @Test("An explicit false is preserved, not overwritten by the default")
    func explicitFalseSurvives() throws {
        let json = Data(#"{"data":{"id":1,"name":"A"},"success":false}"#.utf8)
        let response = try JSONDecoder.echno.decode(APIResponse<Payload>.self, from: json)
        #expect(!response.success)
    }

    @Test("A missing payload fails rather than yielding an empty value")
    func missingDataThrows() {
        let json = Data(#"{"message":"ok","success":true}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder.echno.decode(APIResponse<Payload>.self, from: json)
        }
    }

    @Test("An acknowledgement decodes with or without its fields")
    func acknowledgement() throws {
        let full = try JSONDecoder.echno.decode(
            APIAcknowledgement.self,
            from: Data(#"{"message":"deleted","success":true}"#.utf8)
        )
        #expect(full.message == "deleted")
        #expect(full.success)

        let bare = try JSONDecoder.echno.decode(APIAcknowledgement.self, from: Data("{}".utf8))
        #expect(bare.message == nil)
        #expect(bare.success)
    }
}

@Suite("Redaction")
struct RedactionTests {

    @Test("A credential never appears whole in a redacted string")
    func neverLeaksWholeValue() {
        let token = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJl"
        let redacted = Log.redacted(token)
        #expect(!redacted.contains(token))
        #expect(redacted.count < token.count)
    }

    @Test("Enough survives to tell two credentials apart")
    func staysDistinguishable() {
        let first = Log.redacted("aaaabbbbccccdddd")
        let second = Log.redacted("aaaabbbbccccEEEE")
        #expect(first != second)
    }

    @Test("A value too short to redact safely is replaced entirely")
    func shortValuesFullyMasked() {
        // With 4 visible characters at each end, anything up to 8 characters
        // would be shown in full. Those must be masked, not abbreviated.
        #expect(Log.redacted("short") == "***")
        #expect(Log.redacted("12345678") == "***")
        #expect(Log.redacted("") == "***")
    }

    @Test("The visible window is configurable and respected")
    func honoursVisibleCount() {
        #expect(Log.redacted("abcdefghijklmnop", keeping: 2) == "ab…op")
    }
}
