import Foundation

/// The error every Echno network failure is surfaced as.
///
/// The generated `EchnoAPI` client raises transport and status errors in its
/// own vocabulary; the middleware maps them onto this so the app has one error
/// type to switch on.
///
/// Prefer the `is*` flags over comparing ``status`` directly — they stay
/// meaningful when `status` is `0` (network failure) or `504` (client-side
/// timeout), neither of which the backend ever actually sends.
public struct APIError: Error, Hashable, Sendable {

    /// HTTP status code of the failed response. `0` for network errors.
    public let status: Int

    /// Human-readable message, from the backend payload where present.
    public let message: String

    /// Additional detail string from the backend error payload.
    public let details: String?

    /// Per-field validation errors, present on 400/422 responses.
    public let fieldErrors: [String: [String]]

    public init(
        message: String,
        status: Int,
        details: String? = nil,
        fieldErrors: [String: [String]] = [:]
    ) {
        self.message = message
        self.status = status
        self.details = details
        self.fieldErrors = fieldErrors
    }

    /// `true` for 401 and 403 responses.
    public var isAuthError: Bool { status == 401 || status == 403 }

    /// `true` for 404 responses.
    public var isNotFound: Bool { status == 404 }

    /// `true` for 5xx responses.
    public var isServerError: Bool { status >= 500 && status < 600 }

    /// `true` when the request was aborted by a client-side timeout.
    ///
    /// Distinct from a server 504: the request never completed, so it may or
    /// may not have been applied on the backend. Callers retrying a mutation
    /// after a timeout need an idempotency key.
    public var isTimeout: Bool { status == Self.timeoutStatus }

    /// `true` when no HTTP response was received at all.
    public var isNetworkFailure: Bool { status == 0 }

    private static let timeoutStatus = 504

    /// A client-side request timeout.
    public static func timeout(_ message: String = "Request timeout") -> APIError {
        APIError(message: message, status: timeoutStatus)
    }

    /// A network-level failure — no HTTP response was received.
    public static func network(_ message: String = "Network error") -> APIError {
        APIError(message: message, status: 0)
    }

    /// A response body that could not be decoded into the expected type.
    public static func decoding(_ message: String) -> APIError {
        APIError(message: message, status: 0, details: "decoding")
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? { message }
    public var failureReason: String? { details }
}

/// The error envelope the Spring Boot backend returns on failure.
struct APIErrorPayload: Decodable {
    let message: String?
    let error: String?
    let status: Int?
    let details: String?
    let errors: [String: [String]]?
}
