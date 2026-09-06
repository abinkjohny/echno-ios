import Foundation

/// Keycloak's token endpoint over `URLSession`.
public struct URLSessionTokenEndpoint: TokenEndpoint {

    private let configuration: KeycloakConfiguration
    private let session: URLSession
    private let now: @Sendable () -> Date

    /// - Parameter now: Injectable so token expiry arithmetic is testable
    ///   without depending on the wall clock.
    public init(
        configuration: KeycloakConfiguration,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date.now }
    ) {
        self.configuration = configuration
        self.session = session
        self.now = now
    }

    public func exchange(code: String, verifier: String) async throws -> TokenSet {
        try await post(
            configuration.tokenEndpoint,
            form: configuration.tokenExchangeForm(code: code, verifier: verifier)
        ).tokenSet(issuedAt: now())
    }

    public func refresh(refreshToken: String) async throws -> TokenSet {
        try await post(
            configuration.tokenEndpoint,
            form: configuration.refreshForm(refreshToken: refreshToken)
        )
        // Keycloak omits refresh_token when rotation is off; keep the one we
        // already hold rather than losing the ability to refresh again.
        .tokenSet(issuedAt: now(), fallbackRefreshToken: refreshToken)
    }

    public func endSession(refreshToken: String) async throws {
        _ = try await send(
            configuration.endSessionEndpoint,
            form: configuration.endSessionForm(refreshToken: refreshToken)
        )
    }

    // MARK: Transport

    private func post(_ url: URL, form: [URLQueryItem]) async throws -> TokenResponse {
        let data = try await send(url, form: form)
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw AuthError.malformedTokenResponse
        }
        return response
    }

    private func send(_ url: URL, form: [URLQueryItem]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = FormBody.encode(form)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            // Transient. The caller keeps the session so the next attempt can
            // succeed; treating this as terminal would sign people out whenever
            // they walked into a lift.
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.malformedTokenResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(from: data, status: http.statusCode)
        }
        return data
    }

    /// Turns a non-2xx token response into the right kind of failure.
    ///
    /// The distinction that matters is `invalid_grant` — a spent, revoked or
    /// expired token — which is terminal and must end the session. Everything
    /// else is reported as-is so a 5xx at the identity provider does not look
    /// like the user's session ending.
    static func failure(from data: Data, status: Int) -> any Error {
        guard let failure = try? JSONDecoder().decode(TokenErrorResponse.self, from: data) else {
            return AuthError.provider("Sign-in service returned \(status).")
        }
        if failure.isInvalidGrant {
            return AuthError.sessionExpired
        }
        return AuthError.provider(failure.errorDescription ?? failure.error)
    }
}
