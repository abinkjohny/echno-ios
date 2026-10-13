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

    /// The phase lives in ``EchnoKit`` as ``SessionPhase`` rather than here,
    /// because what the root of the app shows for each one is a decision worth
    /// testing and the app target has no test bundle.
    private(set) var phase: SessionPhase = .initial

    /// The last failure worth showing. Cleared when a new attempt starts, and
    /// never set for a cancellation — dismissing the sheet is a decision, not
    /// an error to apologise for.
    var error: String?

    /// The signed-in user, for any screen that needs it.
    ///
    /// Owned here because its lifetime is the session's: it is cleared on
    /// sign-out, and a store that outlived the session would show the previous
    /// user behind the next sign-in screen.
    let users: UserStore

    /// The organizations this user belongs to, and which one the app is acting
    /// in. Owned here for the same reason as ``users``: its lifetime is the
    /// session's, and a tenant list that outlived sign-out would offer the
    /// previous user's sites to the next one.
    let organizations: OrganizationStore

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
        let credentials = SessionCredentials(authenticator: authenticator)
        let client = EchnoClient.make(environment: server, credentials: credentials)
        self.credentials = credentials
        self.client = client
        self.users = UserStore(loader: UserService(client: client))
        self.organizations = OrganizationStore(loader: OrganizationService(client: client))
    }

    /// Restores a session left by a previous launch.
    ///
    /// Asking for a token is the honest test: a stored set that cannot be
    /// refreshed is not a session, and finding that out now is better than on
    /// the user's first tap.
    func restore() async {
        do {
            _ = try await authenticator.validAccessToken()
            phase = .signedIn
        } catch {
            phase = .signedOut
        }
    }

    /// Whether a launch is still deciding. Read by the root so the splash
    /// stands in for a screen rather than being layered over one.
    var isRestoring: Bool { phase == .restoring }

    func signIn() async {
        error = nil
        phase = .signingIn
        do {
            _ = try await authenticator.signIn()
            phase = .signedIn
        } catch AuthError.cancelled {
            phase = .signedOut
        } catch {
            phase = .signedOut
            self.error = (error as? LocalizedError)?.errorDescription
                ?? "Sign-in could not be completed."
        }
    }

    func signOut() async {
        try? await authenticator.signOut()
        await credentials.select(organization: nil)
        // Not housekeeping: without this the next sign-in screen renders with
        // the previous user's name and email still in the store behind it.
        users.clear()
        organizations.clear()
        phase = .signedOut
    }

    /// Loads the user's organizations and tells the networking layer which one
    /// to scope requests to.
    ///
    /// Two steps, not one. The store decides *what* is selected; the credential
    /// provider is what actually puts `X-Organization-Id` on a request, and it
    /// is an actor. Keeping the push here means no view has to know that the
    /// tenant header exists.
    ///
    /// A selection that stays `nil` is left alone deliberately — the user
    /// belongs to several organizations and has not chosen. Sending a header
    /// then would pick a tenant on their behalf.
    func loadOrganizations() async {
        guard let user = users.currentUser else { return }
        await organizations.load(forUser: user.id, preferring: user.defaultOrganizationID)
        await syncSelectedOrganization()
    }

    /// Acts in `id`, if the user belongs to it.
    func select(organization id: Int64) async {
        organizations.select(id: id)
        await syncSelectedOrganization()
    }

    private func syncSelectedOrganization() async {
        await credentials.select(organization: organizations.selected?.id)
    }

    /// Redeems an invite code and starts acting in the organization it granted.
    ///
    /// The order here is the whole substance of this method, and getting it
    /// wrong produces a join that appears to work and then refuses every
    /// request:
    ///
    /// 1. Redeem. Until this succeeds nothing has happened, so a failure is
    ///    safe for the user to retry with another code.
    /// 2. **Renew the access token.** Membership is granted by adding the user
    ///    to a Keycloak group, and the `ORG_MEMBER_<id>` authority
    ///    `TenantFilter` checks is a claim in the token. The token in hand was
    ///    issued before the join, so it cannot carry the new membership, and
    ///    because it has not expired nothing would otherwise replace it. Every
    ///    request scoped to the new organization would be answered 403 until
    ///    the next genuine expiry.
    /// 3. Adopt and scope. Only now is the credential good for the tenant
    ///    header that adopting sets.
    ///
    /// A renewal that fails is reported separately rather than as a failed
    /// join, because the membership is real by then. Telling the user it failed
    /// would invite them to redeem the code again, which the backend answers
    /// with a 500 for an existing membership (ask #22) — a confusing end to an
    /// operation that actually succeeded.
    ///
    /// - Returns: The organization that was joined.
    /// - Throws: ``APIError`` from redemption, or one describing a join that
    ///   succeeded while the session could not be refreshed.
    func join(using code: InviteCode) async throws -> Organization {
        guard let user = users.currentUser else {
            throw APIError(
                message: "Your profile is still loading. Try again in a moment.",
                status: 0
            )
        }

        let organization = try await InvitationService(client: client)
            .join(using: code, asUser: user.id)

        do {
            _ = try await authenticator.renewAccessToken()
        } catch {
            // Adopted anyway: the membership exists on the server, and a store
            // that denied it would disagree with the next successful load.
            await adopt(organization)
            throw APIError(
                message: """
                    You have joined \(organization.name), but your access could not be                     refreshed. Sign out and sign in again to start working in it.
                    """,
                status: 0
            )
        }

        await adopt(organization)
        return organization
    }

    private func adopt(_ organization: Organization) async {
        organizations.adopt(organization)
        await syncSelectedOrganization()
    }

    /// Registers an account, then hands straight to the hosted sign-in — the
    /// same sequence echno-web uses, so a new user is not left at a form
    /// wondering whether it worked.
    func register(_ draft: RegistrationDraft) async throws {
        try await RegistrationService(client: client).register(draft)
    }
}
