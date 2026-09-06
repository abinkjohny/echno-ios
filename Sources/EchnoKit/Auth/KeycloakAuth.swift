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
}
