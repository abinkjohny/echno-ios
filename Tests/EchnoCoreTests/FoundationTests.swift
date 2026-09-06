import Foundation
import Testing
@testable import EchnoCore

@Suite("Endpoint family selection")
struct EndpointsTests {

    @Test("Unmigrated modules route to the web controller")
    func webByDefault() {
        #expect(Endpoints.path("materials") == "materials/web")
        #expect(Endpoints.path("materials", "/low-stock") == "materials/web/low-stock")
        #expect(Endpoints.family(for: "vendors") == .web)
    }

    @Test("Cleared modules route to the mobile controller")
    func mobileWhenReady() {
        #expect(Endpoints.path("attendance") == "attendance")
        #expect(Endpoints.path("attendance", "/check-in") == "attendance/check-in")
        #expect(Endpoints.family(for: "attendance") == .mobile)
    }

    @Test("A suffix without a leading slash is still joined correctly")
    func suffixNormalisation() {
        #expect(Endpoints.path("materials", "low-stock") == "materials/web/low-stock")
    }
}

@Suite("Backend date decoding")
struct DateDecodingTests {

    private struct Wrapper: Decodable { let at: Date }

    private func decode(_ raw: String) throws -> Date {
        let json = Data(#"{"at":"\#(raw)"}"#.utf8)
        return try JSONDecoder.echno.decode(Wrapper.self, from: json).at
    }

    /// Builds the expected instant from components rather than a hand-computed
    /// epoch number — the magic number is exactly the thing most likely to be
    /// wrong, and a wrong constant here would look like a decoder bug.
    private func utc(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return try #require(calendar.date(from: components))
    }

    @Test("Instant with fractional seconds")
    func fractional() throws {
        let expected = try utc(2026, 9, 6, 14, 23, 5).addingTimeInterval(0.123)
        let date = try decode("2026-09-06T14:23:05.123Z")
        #expect(abs(date.timeIntervalSince(expected)) < 0.001)
    }

    @Test("Instant without fractional seconds")
    func whole() throws {
        let date = try decode("2026-09-06T14:23:05Z")
        #expect(try date == utc(2026, 9, 6, 14, 23, 5))
    }

    @Test("LocalDateTime, no zone, read as UTC")
    func localDateTime() throws {
        let date = try decode("2026-09-06T14:23:05")
        #expect(try date == utc(2026, 9, 6, 14, 23, 5))
    }

    @Test("LocalDate, read as UTC midnight")
    func localDate() throws {
        let date = try decode("2026-09-06")
        #expect(try date == utc(2026, 9, 6))
    }

    @Test("A zoned instant and its unzoned twin agree")
    func zonedAndUnzonedAgree() throws {
        #expect(try decode("2026-09-06T14:23:05Z") == decode("2026-09-06T14:23:05"))
    }

    @Test("An unrecognised format fails loudly")
    func unknownFormat() {
        #expect(throws: DecodingError.self) { try decode("06/09/2026") }
    }

    @Test("A date survives an encode/decode round trip")
    func roundTrip() throws {
        struct Box: Codable { let at: Date }
        let original = try utc(2026, 9, 6, 14, 23, 5)
        let data = try JSONEncoder.echno.encode(Box(at: original))
        let decoded = try JSONDecoder.echno.decode(Box.self, from: data)
        #expect(abs(decoded.at.timeIntervalSince(original)) < 0.001)
    }
}

@Suite("APIError classification")
struct APIErrorTests {

    @Test("Status codes map to the right flags")
    func flags() {
        #expect(APIError(message: "", status: 401).isAuthError)
        #expect(APIError(message: "", status: 403).isAuthError)
        #expect(APIError(message: "", status: 404).isNotFound)
        #expect(APIError(message: "", status: 500).isServerError)
        #expect(!APIError(message: "", status: 200).isServerError)
    }

    @Test("Timeout and network failure stay distinguishable")
    func syntheticStatuses() {
        #expect(APIError.timeout().isTimeout)
        #expect(APIError.network().isNetworkFailure)
        #expect(!APIError.network().isTimeout)
    }

    @Test("A backend error envelope decodes into field errors")
    func envelopeDecoding() throws {
        let json = Data("""
        {"message":"Validation failed","status":400,"errors":{"name":["must not be blank"]}}
        """.utf8)
        let payload = try JSONDecoder.echno.decode(APIErrorPayload.self, from: json)
        #expect(payload.message == "Validation failed")
        #expect(payload.errors?["name"] == ["must not be blank"])
    }
}

@Suite("Multipart encoding")
struct MultipartTests {

    @Test("Parts are framed with the boundary and closed")
    func framing() throws {
        let body = MultipartPart.encode(
            [
                .text("data", #"{"employeeId":1}"#),
                .file("photo", filename: "selfie.jpg", contentType: "image/jpeg", data: Data([0xFF, 0xD8]))
            ],
            boundary: "B"
        )
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("--B\r\nContent-Disposition: form-data; name=\"data\""))
        #expect(text.contains("name=\"photo\"; filename=\"selfie.jpg\""))
        #expect(text.contains("Content-Type: image/jpeg"))
        #expect(text.hasSuffix("--B--\r\n"))
    }
}

@Suite("Token expiry")
struct TokenSetTests {

    @Test("Leeway expires the token early")
    func leeway() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let tokens = TokenSet(
            accessToken: "a",
            refreshToken: "r",
            idToken: nil,
            expiresAt: now.addingTimeInterval(20)
        )
        #expect(tokens.isExpired(now: now, leeway: 30))
        #expect(!tokens.isExpired(now: now, leeway: 5))
    }
}
