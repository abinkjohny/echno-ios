import Foundation
import Observation
import EchnoKit
import EchnoAPI

/// The app's session state, and the single place the auth stack is assembled.
///
/// Owns *state*, not presentation: it exposes what happened, and the views
/// decide how to say it. Errors are held rather than thrown so a view can
/// render them without a `do/catch` in the body.
@Observable
@MainActor
final class AuthSession {

    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn
    }

    private(set) var state: State = .signedOut

    /// The last failure worth showing. Cleared when a new attempt starts, and
    /// never set for a cancellation — dismissing the sheet is a decision, not
    /// an error to apologise for.
    var error: String?

    private let authenticator: KeycloakAuthenticator
    private let credentials: SessionCredentials
    private let client: Client

    init(
        configuration: KeycloakConfiguration = EchnoConfiguration.keycloak,
        server: ServerEnvironment = EchnoConfiguration.server,
        store: any TokenStoring = KeychainTokenStore(),
        browser: any WebAuthenticationPresenting = WebAuthenticationSessionPresenter()
    ) {
        let authenticator = KeycloakAuthenticator(
            configuration: configuration,
            endpoint: URLSessionTokenEndpoint(configuration: configuration),
            store: store,
            browser: browser
        )
        self.authenticator = authenticator
        self.credentials = SessionCredentials(authenticator: authenticator)
        self.client = EchnoClient.make(environment: server, credentials: credentials)
    }

    /// Restores a session left by a previous launch.
    ///
    /// Asking for a token is the honest test: a stored set that cannot be
    /// refreshed is not a session, and finding that out now is better than on
    /// the user's first tap.
    func restore() async {
        do {
            _ = try await authenticator.validAccessToken()
            state = .signedIn
        } catch {
            state = .signedOut
        }
    }

    func signIn() async {
        error = nil
        state = .signingIn
        do {
            _ = try await authenticator.signIn()
            state = .signedIn
        } catch AuthError.cancelled {
            state = .signedOut
        } catch {
            state = .signedOut
            self.error = (error as? LocalizedError)?.errorDescription
                ?? "Sign-in could not be completed."
        }
    }

    func signOut() async {
        try? await authenticator.signOut()
        await credentials.select(organization: nil)
        state = .signedOut
    }

    /// Registers an account, then hands straight to the hosted sign-in — the
    /// same sequence echno-web uses, so a new user is not left at a form
    /// wondering whether it worked.
    func register(_ draft: RegistrationDraft) async throws {
        try await RegistrationService(client: client).register(draft)
    }
}
