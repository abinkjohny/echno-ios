import Foundation

/// Supplies the generated client with a token and the active tenant.
///
/// The two are separate concerns deliberately. The token comes from the
/// authenticator, which owns refresh; the organization is chosen by the user
/// after sign-in and can change without touching the session.
public actor SessionCredentials: APICredentialProvider {

    private let authenticator: any AuthenticationService
    private var organizationID: Int64?

    public init(authenticator: any AuthenticationService, organizationID: Int64? = nil) {
        self.authenticator = authenticator
        self.organizationID = organizationID
    }

    /// Forwards to the authenticator, which refreshes if needed and serialises
    /// concurrent refreshes into one.
    public func accessToken() async throws -> String {
        try await authenticator.validAccessToken()
    }

    public func currentOrganizationID() async -> Int64? {
        organizationID
    }

    /// Switches the tenant every subsequent request acts in.
    ///
    /// `nil` during bootstrap, before the user has an organization. The backend
    /// rejects a request from a multi-organization user that omits the header,
    /// so this must be set before any tenant-scoped call.
    public func select(organization id: Int64?) {
        organizationID = id
    }
}
