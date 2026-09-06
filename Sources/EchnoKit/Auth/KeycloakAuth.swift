import Foundation

/// Where the Keycloak realm lives and how this client identifies itself.
///
/// Values come from the app's build configuration, never from source. The iOS
/// client is a **public** client using authorization code + PKCE, so it holds
/// no secret — see `local-docs/ios-action-plan.md` §3.
public struct KeycloakConfiguration: Sendable, Equatable {

    /// e.g. `https://auth.echno.in/realms/echno-realm`
    public let issuer: URL

    /// The public client registered for iOS, e.g. `echno-ios`.
    public let clientID: String

    /// Must match the client's registered redirect URI and the app's
    /// `CFBundleURLSchemes`, e.g. `com.tornotron.echno-ios://oauth/callback`.
    public let redirectURI: URL

    /// Scopes requested at sign-in.
    public let scopes: [String]

    public init(
        issuer: URL,
        clientID: String,
        redirectURI: URL,
        scopes: [String] = ["openid", "profile", "email", "offline_access"]
    ) {
        self.issuer = issuer
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }

    public var authorizationEndpoint: URL {
        issuer.appending(path: "protocol/openid-connect/auth")
    }

    public var tokenEndpoint: URL {
        issuer.appending(path: "protocol/openid-connect/token")
    }

    public var endSessionEndpoint: URL {
        issuer.appending(path: "protocol/openid-connect/logout")
    }

    /// The URL to open in the browser to begin sign-in.
    ///
    /// - Parameters:
    ///   - pkce: The pair for this attempt. Only its challenge is sent.
    ///   - state: An unguessable value echoed back in the callback, checked by
    ///     ``AuthorizationCallback`` to prove the redirect answers this request.
    public func authorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: PKCE.method)
        ]
        return components.url!
    }
}

/// The sign-in / refresh / sign-out surface the app talks to.
///
/// - Note: **Phase 1 implements this** with `ASWebAuthenticationSession` for
///   the authorization-code + PKCE flow. Two properties matter and are easy to
///   get wrong, so they are called out here rather than discovered later:
///
///   1. **Single-flight refresh.** Concurrent 401s must trigger *one* refresh,
///      not one per request — Keycloak rotates the refresh token, so the second
///      caller would present a spent one and lose the session. echno-web's
///      `lib/auth/refresh-access-token.ts` is the reference.
///   2. **Retry only what is worth retrying.** A network blip is retryable; an
///      `invalid_grant` is terminal and must sign the user out rather than
///      spin.
public protocol AuthenticationService: Sendable {

    /// Presents the hosted login and exchanges the resulting code for tokens.
    func signIn() async throws -> TokenSet

    /// Returns a valid access token, refreshing first if needed.
    ///
    /// This is what ``APICredentialProvider/accessToken()`` forwards to.
    func validAccessToken() async throws -> String

    /// Clears local tokens and ends the Keycloak session.
    func signOut() async throws
}

/// Failures specific to the auth flow, distinct from ``APIError`` so the UI can
/// tell "your session ended" apart from "that request failed".
public enum AuthError: Error, Sendable, Equatable {
    /// The user dismissed the hosted login.
    case cancelled
    /// The refresh token was rejected — the session is over, sign in again.
    case sessionExpired
    /// Keycloak returned an error response.
    case provider(String)
    /// The Keychain refused a read or write.
    case keychain(OSStatus)
    /// The callback's `state` was absent or did not match the one we issued.
    /// Treated as hostile, not as a glitch.
    case stateMismatch
    /// The callback carried neither an authorization code nor an error.
    case missingAuthorizationCode
    /// A PKCE verifier outside the length RFC 7636 permits.
    case invalidVerifier
    /// The token endpoint returned something that is not a token response.
    case malformedTokenResponse
}

extension AuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled."
        case .sessionExpired: "Your session has ended. Please sign in again."
        case .provider(let message): message
        case .keychain: "The device could not store your session securely."
        case .stateMismatch: "The sign-in response could not be verified."
        case .missingAuthorizationCode: "The sign-in response was incomplete."
        case .invalidVerifier: "The sign-in request could not be prepared."
        case .malformedTokenResponse: "The sign-in service returned an unexpected response."
        }
    }
}
