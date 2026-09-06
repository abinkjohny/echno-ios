import Foundation

/// Talks to Keycloak's token endpoint.
///
/// A protocol so the authenticator's logic — single-flight refresh, session
/// teardown, error classification — is testable without a network.
public protocol TokenEndpoint: Sendable {
    func exchange(code: String, verifier: String) async throws -> TokenSet
    func refresh(refreshToken: String) async throws -> TokenSet
    func endSession(refreshToken: String) async throws
}

/// Presents the hosted login and returns the redirect it lands on.
///
/// `ASWebAuthenticationSession` lives in the app target; keeping this a protocol
/// means `EchnoKit` imports no UI framework and the sign-in flow can be driven
/// from tests with a scripted callback.
public protocol WebAuthenticationPresenting: Sendable {

    /// - Parameters:
    ///   - url: The authorization URL to open.
    ///   - callbackScheme: The custom scheme the redirect will use.
    /// - Returns: The redirect URL the session completed on.
    /// - Throws: ``AuthError/cancelled`` if the user dismissed it.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// The Keycloak session: sign in, keep the access token fresh, sign out.
///
/// An `actor` for one specific reason. Keycloak rotates refresh tokens, so a
/// second concurrent refresh presents one the first has already spent, Keycloak
/// answers `invalid_grant`, and the user is signed out in the middle of a
/// session. Serialising refreshes here — and reusing the in-flight one rather
/// than starting another — is what prevents that.
public actor KeycloakAuthenticator: AuthenticationService {

    private let configuration: KeycloakConfiguration
    private let endpoint: any TokenEndpoint
    private let store: any TokenStoring
    private let browser: any WebAuthenticationPresenting

    /// The refresh currently in flight, if any. Every caller that arrives while
    /// it runs awaits this rather than starting its own.
    private var refreshInFlight: Task<TokenSet, any Error>?

    public init(
        configuration: KeycloakConfiguration,
        endpoint: any TokenEndpoint,
        store: any TokenStoring,
        browser: any WebAuthenticationPresenting
    ) {
        self.configuration = configuration
        self.endpoint = endpoint
        self.store = store
        self.browser = browser
    }

    // MARK: Sign in

    /// Runs the authorization-code flow with PKCE and stores the result.
    public func signIn() async throws -> TokenSet {
        let pkce = PKCE()
        let state = Self.makeState()

        let callback = try await browser.authenticate(
            url: configuration.authorizationURL(pkce: pkce, state: state),
            callbackScheme: try configuration.callbackScheme()
        )

        let code = try AuthorizationCallback.code(from: callback, expectedState: state)
        let tokens = try await endpoint.exchange(code: code, verifier: pkce.verifier)
        try await store.save(tokens)
        Log.auth.info("Signed in; access token \(Log.redacted(tokens.accessToken), privacy: .public)")
        return tokens
    }

    // MARK: Access

    /// A valid access token, refreshing first if the held one has expired.
    public func validAccessToken() async throws -> String {
        guard let tokens = try await store.load() else {
            throw AuthError.sessionExpired
        }
        if !tokens.isExpired() {
            return tokens.accessToken
        }
        return try await refresh(using: tokens).accessToken
    }

    /// Refreshes, joining the in-flight attempt when there is one.
    private func refresh(using tokens: TokenSet) async throws -> TokenSet {
        if let existing = refreshInFlight {
            return try await existing.value
        }

        guard let refreshToken = tokens.refreshToken else {
            // Nothing to refresh with. Clearing avoids leaving a dead session
            // that fails identically on every later call.
            try? await store.clear()
            throw AuthError.sessionExpired
        }

        let task = Task<TokenSet, any Error> { [endpoint, store] in
            do {
                let refreshed = try await endpoint.refresh(refreshToken: refreshToken)
                try await store.save(refreshed)
                return refreshed
            } catch {
                // A rejected grant is terminal — the token is spent, revoked or
                // expired, and retrying cannot help. Anything else may be
                // transient, so the session is left intact for the next attempt.
                if Self.isTerminal(error) {
                    try? await store.clear()
                    throw AuthError.sessionExpired
                }
                throw error
            }
        }

        refreshInFlight = task
        defer { refreshInFlight = nil }
        return try await task.value
    }

    // MARK: Sign out

    /// Ends the Keycloak session and clears the device.
    ///
    /// The local clear happens whatever the network does. Keeping tokens because
    /// a request failed would leave the app looking signed in, and signing out
    /// has to work offline.
    public func signOut() async throws {
        let tokens = try? await store.load()
        defer { refreshInFlight = nil }

        if let refreshToken = tokens?.refreshToken {
            do {
                try await endpoint.endSession(refreshToken: refreshToken)
            } catch {
                Log.auth.warning("Could not end the remote session: \(error.localizedDescription, privacy: .public)")
            }
        }
        try await store.clear()
    }

    // MARK: Helpers

    /// An unguessable value echoed back in the callback, so a redirect can be
    /// tied to the request that started it.
    private static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64URLEncodedString()
    }

    private static func isTerminal(_ error: any Error) -> Bool {
        if let authError = error as? AuthError {
            return authError == .sessionExpired || authError == .malformedTokenResponse
        }
        return false
    }
}
