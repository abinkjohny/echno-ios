import Foundation

/// Reads the redirect Keycloak sends back after the hosted login.
public enum AuthorizationCallback {

    /// Extracts the authorization code, having first checked the callback is one
    /// we asked for.
    ///
    /// - Parameters:
    ///   - url: The redirect URL the web authentication session returned.
    ///   - expectedState: The `state` sent with the authorization request.
    /// - Returns: The authorization code, ready to exchange for tokens.
    /// - Throws: ``AuthError/provider(_:)`` when Keycloak reported an error,
    ///   ``AuthError/stateMismatch`` when the callback is not ours, and
    ///   ``AuthError/missingAuthorizationCode`` when it carries neither.
    public static func code(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }

        // State first, and before anything else is read. It is the CSRF
        // defence: without it an attacker can hand the app a callback carrying
        // their own authorization code, and the app would happily sign the user
        // into the attacker's account.
        guard let state = value("state"), state == expectedState else {
            throw AuthError.stateMismatch
        }

        if let error = value("error") {
            throw AuthError.provider(value("error_description") ?? error)
        }

        guard let code = value("code"), !code.isEmpty else {
            throw AuthError.missingAuthorizationCode
        }
        return code
    }
}
