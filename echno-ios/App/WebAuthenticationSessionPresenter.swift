import AuthenticationServices
import Foundation
import EchnoKit

/// Presents Keycloak's hosted login in `ASWebAuthenticationSession`.
///
/// This is the only place the app touches AuthenticationServices, which is why
/// `EchnoKit` can stay free of UI frameworks and the sign-in flow can be driven
/// from tests with a scripted callback.
///
/// `prefersEphemeralWebBrowserSession` is left **off** on purpose. Sharing the
/// browser's cookie jar is what lets an already-signed-in user through without
/// retyping anything, and what makes SSO work at all. The trade is that signing
/// out has to end the session at Keycloak too, not merely drop local tokens —
/// ``KeycloakAuthenticator/signOut()`` does.
final class WebAuthenticationSessionPresenter: NSObject, WebAuthenticationPresenting {

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // Hop to the main actor: ASWebAuthenticationSession must be started
            // there, and it needs a window to anchor to.
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme
                ) { callback, error in
                    if let callback {
                        continuation.resume(returning: callback)
                    } else if let error = error as? ASWebAuthenticationSessionError,
                              error.code == .canceledLogin {
                        // Dismissing the sheet is a normal outcome, not a
                        // failure to report.
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(
                            throwing: AuthError.provider(
                                error?.localizedDescription ?? "Sign-in could not be completed."
                            )
                        )
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false

                guard session.start() else {
                    continuation.resume(
                        throwing: AuthError.provider("Sign-in could not be started.")
                    )
                    return
                }
            }
        }
    }
}

extension WebAuthenticationSessionPresenter: ASWebAuthenticationPresentationContextProviding {
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
