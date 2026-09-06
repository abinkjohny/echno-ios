import Foundation

/// A set of OAuth tokens plus the moment the access token stops being valid.
public struct TokenSet: Sendable, Equatable, Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let expiresAt: Date

    public init(
        accessToken: String,
        refreshToken: String?,
        idToken: String?,
        expiresAt: Date
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.expiresAt = expiresAt
    }

    /// Treats the token as expired slightly early, so a request started now
    /// does not arrive after expiry.
    public func isExpired(now: Date = .now, leeway: TimeInterval = 30) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// Persists the token set across cold launches.
///
/// ``KeychainTokenStore`` is the real implementation; ``EphemeralTokenStore``
/// exists for tests and previews.
public protocol TokenStoring: Sendable {
    func load() async throws -> TokenSet?
    func save(_ tokens: TokenSet) async throws
    func clear() async throws
}

/// In-memory ``TokenStoring`` for tests and previews. Never use in the app —
/// it loses the session on every launch.
public actor EphemeralTokenStore: TokenStoring {
    private var tokens: TokenSet?

    public init(tokens: TokenSet? = nil) {
        self.tokens = tokens
    }

    public func load() async throws -> TokenSet? { tokens }
    public func save(_ tokens: TokenSet) async throws { self.tokens = tokens }
    public func clear() async throws { tokens = nil }
}
