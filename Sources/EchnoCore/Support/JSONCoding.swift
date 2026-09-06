import Foundation

// `JSONDecoder`, `JSONEncoder` and `DateFormatter` are `Sendable` in the
// current SDK, so they need no annotation. `ISO8601DateFormatter` is not, and
// Swift 6 rejects it as a shared `static let` — the two below carry
// `nonisolated(unsafe)` to assert what is actually true of them: each is fully
// configured inside its initialiser and only ever read afterwards, which
// Foundation documents as safe for concurrent use.
//
// Building a coder per call would sidestep the annotation but is not free —
// decoding is on the hot path of every list screen. If one of these ever needs
// reconfiguring at runtime it must move behind an actor rather than be mutated
// in place.

/// The single decoder every service uses.
///
/// Do not build per-call decoders: date handling has to be identical everywhere
/// or two modules will disagree about the same timestamp.
extension JSONDecoder {
    public static let echno: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(EchnoDate.decode)
        return decoder
    }()
}

/// The matching encoder.
extension JSONEncoder {
    public static let echno: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom(EchnoDate.encode)
        return encoder
    }()
}

/// Date handling for the Spring Boot backend.
///
/// The backend is not uniform: `Instant` fields serialise with fractional
/// seconds and a `Z`, `LocalDateTime` fields serialise without a zone, and
/// `LocalDate` fields are a plain `yyyy-MM-dd`. Decoding tries each in turn
/// rather than failing a whole payload on the first mismatch.
public enum EchnoDate {

    /// `2026-09-06T14:23:05.123Z` — `Instant`.
    public nonisolated(unsafe) static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// `2026-09-06T14:23:05Z` — `Instant` without fractional seconds.
    public nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// `2026-09-06T14:23:05` — `LocalDateTime`, no zone. Read as UTC.
    public static let localDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    /// `2026-09-06` — `LocalDate`. Read as UTC midnight.
    public static let localDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func decode(_ decoder: any Decoder) throws -> Date {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let date = iso8601Fractional.date(from: raw) { return date }
        if let date = iso8601.date(from: raw) { return date }
        if let date = localDateTime.date(from: raw) { return date }
        if let date = localDate.date(from: raw) { return date }
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognised date format: \(raw)"
            )
        )
    }

    static func encode(_ date: Date, _ encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso8601Fractional.string(from: date))
    }
}
