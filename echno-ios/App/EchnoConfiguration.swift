import Foundation
import EchnoKit

/// Where this build points and how it identifies itself.
///
/// Values come from the Info.plist, injected by `INFOPLIST_KEY_*` build
/// settings, so a build can be pointed at a local backend without editing
/// source. None of them is a secret: the iOS Keycloak client is public and uses
/// PKCE, so it holds no client secret by design — see `CLAUDE.md` § Security.
enum EchnoConfiguration {

    static var keycloak: KeycloakConfiguration {
        KeycloakConfiguration(
            issuer: url(for: "ECHNO_KEYCLOAK_ISSUER", default: defaultIssuer),
            clientID: string(for: "ECHNO_KEYCLOAK_CLIENT_ID", default: "echno-ios-client"),
            redirectURI: url(for: "ECHNO_OAUTH_REDIRECT_URI", default: defaultRedirect)
        )
    }

    static var server: ServerEnvironment {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ECHNO_API_BASE_URL") as? String,
              !raw.isEmpty, let url = URL(string: raw)
        else { return .production }
        return .custom(url)
    }

    // MARK: Defaults

    private static let defaultIssuer = URL(string: "https://auth.echno.in/realms/echno-realm")!

    /// `ASWebAuthenticationSession` intercepts this scheme itself, so it does not
    /// need registering in `CFBundleURLTypes`. It must match the redirect URI on
    /// the Keycloak client exactly.
    private static let defaultRedirect = URL(string: "com.tornotron.echno-ios://oauth/callback")!

    private static func string(for key: String, default fallback: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return (value?.isEmpty == false) ? value! : fallback
    }

    private static func url(for key: String, default fallback: URL) -> URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !raw.isEmpty, let url = URL(string: raw)
        else { return fallback }
        return url
    }
}
