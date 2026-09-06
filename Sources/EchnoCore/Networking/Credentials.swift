import Foundation

/// Supplies the values that vary per request but are owned by the app, not by
/// the networking layer: the bearer token and the active organization.
///
/// The auth layer conforms to this in Phase 1. Keeping it a protocol means the
/// networking layer never depends on the auth stack, and tests inject a stub.
public protocol APICredentialProvider: Sendable {

    /// A valid access token, refreshing it first if it has expired.
    ///
    /// Throws rather than returning `nil` so a failed refresh surfaces at the
    /// call site instead of as a confusing 401 further down.
    func accessToken() async throws -> String

    /// The organization the caller is acting in, sent as `X-Organization-Id`.
    ///
    /// `nil` only during bootstrap, before an organization has been chosen.
    /// The backend's `TenantFilter` 400s a multi-org user who omits it — see
    /// `local-docs/backend-mobile-api-gaps.md` §2.
    func currentOrganizationID() async -> Int64?
}

/// A provider that has no session yet — used before sign-in and in previews.
public struct AnonymousCredentials: APICredentialProvider {
    public init() {}

    public func accessToken() async throws -> String {
        throw APIError(message: "Not signed in", status: 401)
    }

    public func currentOrganizationID() async -> Int64? { nil }
}
