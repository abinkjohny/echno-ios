import Foundation

/// The token endpoint's success response.
///
/// Keycloak speaks snake_case here, unlike the rest of the platform, so the
/// keys are mapped explicitly rather than by a global decoding strategy.
public struct TokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?

    /// Lifetime in seconds, relative to when the response was issued.
    public let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }

    /// Converts to a ``TokenSet`` with an absolute expiry.
    ///
    /// - Parameters:
    ///   - issuedAt: When the response arrived. Injectable so the arithmetic is
    ///     testable without depending on the clock.
    ///   - fallbackRefreshToken: The refresh token already held. Keycloak omits
    ///     `refresh_token` from a refresh response when rotation is disabled;
    ///     treating that as "no refresh token" would end the session at the next
    ///     expiry, so the previous one is retained.
    public func tokenSet(issuedAt: Date, fallbackRefreshToken: String? = nil) -> TokenSet {
        TokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken ?? fallbackRefreshToken,
            idToken: idToken,
            expiresAt: issuedAt.addingTimeInterval(TimeInterval(expiresIn))
        )
    }
}

/// The token endpoint's failure response (RFC 6749 §5.2).
public struct TokenErrorResponse: Decodable, Sendable {
    public let error: String
    public let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    /// Whether the grant itself was rejected.
    ///
    /// This is the terminal case: the refresh token is spent, revoked or
    /// expired, and no amount of retrying will help. The session is over and the
    /// user has to sign in again — distinguishing it from a transient failure is
    /// what stops the app retrying forever behind a spinner.
    public var isInvalidGrant: Bool { error == "invalid_grant" }
}

/// `application/x-www-form-urlencoded` bodies.
public enum FormBody {

    /// Encodes items into a request body.
    ///
    /// Percent-encodes everything outside the unreserved set. `URLComponents`
    /// is deliberately not used: it leaves `+` and `&` unescaped in query
    /// values, which a form body reads as a separator, so a token containing
    /// either would silently truncate.
    public static func encode(_ items: [URLQueryItem]) -> Data {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        let pairs = items.map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? item.name
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(name)=\(value)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}

extension KeycloakConfiguration {

    /// The body that exchanges an authorization code for tokens.
    public func tokenExchangeForm(code: String, verifier: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
    }

    /// The body that trades a refresh token for a new access token.
    public func refreshForm(refreshToken: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
    }

    /// The body that ends the session at Keycloak.
    ///
    /// Clearing local tokens is not signing out. Without this the session stays
    /// live at the identity provider, and the next sign-in attempt is answered
    /// by SSO without asking for credentials.
    public func endSessionForm(refreshToken: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
    }
}
