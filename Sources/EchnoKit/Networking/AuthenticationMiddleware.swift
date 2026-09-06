import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Attaches the caller's identity to every generated request.
///
/// Two headers, both required by the backend on almost every endpoint:
///
/// - `Authorization: Bearer …` — the access token, refreshed first if it has
///   expired. Refresh happens inside the credential provider so it is
///   single-flight; doing it here would fire one refresh per in-flight request
///   and, because Keycloak rotates refresh tokens, lose the session.
/// - `X-Organization-Id` — the active tenant. The backend's `TenantFilter`
///   400s a user who belongs to several organizations and omits it.
///
/// A few endpoints are reachable without a session — registration is the one
/// that matters today. Those are listed in ``unauthenticatedOperations`` and
/// skipped, so the sign-up screen does not have to hold a token it cannot have.
public struct AuthenticationMiddleware: ClientMiddleware {

    /// Operation IDs that must not carry an `Authorization` header.
    ///
    /// Keyed by `operationId` from the OpenAPI document rather than by path, so
    /// a path change on the backend cannot silently start sending a token to an
    /// endpoint that is meant to be anonymous.
    public static let unauthenticatedOperations: Set<String> = [
        "registerUser"   // POST /api/v1/auth/register — permitAll on the backend
    ]

    private let credentials: any APICredentialProvider

    public init(credentials: any APICredentialProvider) {
        self.credentials = credentials
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        if !Self.unauthenticatedOperations.contains(operationID) {
            let token = try await credentials.accessToken()
            request.headerFields[.authorization] = "Bearer \(token)"

            if let organizationID = await credentials.currentOrganizationID() {
                request.headerFields[.xOrganizationID] = String(organizationID)
            }
        }

        return try await next(request, body, baseURL)
    }
}

extension HTTPField.Name {
    /// The tenant selector the backend's `TenantFilter` reads.
    static let xOrganizationID = HTTPField.Name("X-Organization-Id")!
}
