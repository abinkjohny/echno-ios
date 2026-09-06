import Foundation
import Testing
@testable import EchnoKit

private let configuration = KeycloakConfiguration(
    issuer: URL(string: "https://auth.echno.in/realms/echno-realm")!,
    clientID: "echno-ios",
    redirectURI: URL(string: "com.tornotron.echno-ios://oauth/callback")!
)

/// A token endpoint that records what it was asked and answers from a script.
private actor StubTokenEndpoint: TokenEndpoint {
    private(set) var refreshCount = 0
    private(set) var exchangeCount = 0
    private(set) var endSessionCount = 0
    private(set) var lastRefreshToken: String?

    var refreshResult: Result<TokenSet, any Error>
    var exchangeResult: Result<TokenSet, any Error>
    var endSessionError: (any Error)?
    /// Held to force concurrent callers to overlap inside a single refresh.
    var refreshDelay: Duration = .zero

    init(
        refreshResult: Result<TokenSet, any Error> = .success(.stub(accessToken: "refreshed")),
        exchangeResult: Result<TokenSet, any Error> = .success(.stub(accessToken: "exchanged"))
    ) {
        self.refreshResult = refreshResult
        self.exchangeResult = exchangeResult
    }

    func exchange(code: String, verifier: String) async throws -> TokenSet {
        exchangeCount += 1
        return try exchangeResult.get()
    }

    func refresh(refreshToken: String) async throws -> TokenSet {
        refreshCount += 1
        lastRefreshToken = refreshToken
        if refreshDelay != .zero { try? await Task.sleep(for: refreshDelay) }
        return try refreshResult.get()
    }

    func endSession(refreshToken: String) async throws {
        endSessionCount += 1
        if let endSessionError { throw endSessionError }
    }

    func setRefreshDelay(_ delay: Duration) { refreshDelay = delay }
    func setRefreshResult(_ result: Result<TokenSet, any Error>) { refreshResult = result }
    func setEndSessionError(_ error: (any Error)?) { endSessionError = error }
}

/// A lock-guarded slot, so a @Sendable closure can record what it saw.
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T?

    var value: T? {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func set(_ newValue: T) {
        lock.lock(); defer { lock.unlock() }
        storage = newValue
    }
}

/// A browser that returns a scripted callback instead of opening one.
private struct StubBrowser: WebAuthenticationPresenting {
    var callback: (@Sendable (URL) throws -> URL)

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try callback(url)
    }
}

extension TokenSet {
    fileprivate static func stub(
        accessToken: String = "access",
        refreshToken: String? = "refresh",
        expiresIn: TimeInterval = 300
    ) -> TokenSet {
        TokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: nil,
            expiresAt: Date.now.addingTimeInterval(expiresIn)
        )
    }

    fileprivate static func expired(refreshToken: String? = "refresh") -> TokenSet {
        TokenSet(
            accessToken: "stale",
            refreshToken: refreshToken,
            idToken: nil,
            expiresAt: Date.now.addingTimeInterval(-60)
        )
    }
}

private func makeAuthenticator(
    endpoint: StubTokenEndpoint = StubTokenEndpoint(),
    store: EphemeralTokenStore = EphemeralTokenStore(),
    browser: StubBrowser = StubBrowser { _ in
        URL(string: "com.tornotron.echno-ios://oauth/callback?code=c&state=s")!
    }
) -> KeycloakAuthenticator {
    KeycloakAuthenticator(
        configuration: configuration,
        endpoint: endpoint,
        store: store,
        browser: browser
    )
}

@Suite("Access token refresh")
struct AccessTokenTests {

    @Test("A valid cached token is used without touching the network")
    func usesCachedToken() async throws {
        let endpoint = StubTokenEndpoint()
        let store = EphemeralTokenStore(tokens: .stub(accessToken: "cached"))
        let auth = makeAuthenticator(endpoint: endpoint, store: store)

        #expect(try await auth.validAccessToken() == "cached")
        #expect(await endpoint.refreshCount == 0)
    }

    @Test("An expired token is refreshed and the new one persisted")
    func refreshesExpiredToken() async throws {
        let endpoint = StubTokenEndpoint()
        let store = EphemeralTokenStore(tokens: .expired())
        let auth = makeAuthenticator(endpoint: endpoint, store: store)

        #expect(try await auth.validAccessToken() == "refreshed")
        #expect(await endpoint.refreshCount == 1)
        // Persisted, or the next launch would refresh again from a stale token.
        #expect(try await store.load()?.accessToken == "refreshed")
    }

    @Test("Concurrent callers trigger exactly one refresh")
    func singleFlight() async throws {
        // Keycloak rotates refresh tokens. A second concurrent refresh would
        // present a token the first one already spent, Keycloak would answer
        // invalid_grant, and the user would be signed out mid-session. This is
        // the reason the authenticator is an actor.
        let endpoint = StubTokenEndpoint()
        await endpoint.setRefreshDelay(.milliseconds(50))
        let auth = makeAuthenticator(endpoint: endpoint, store: EphemeralTokenStore(tokens: .expired()))

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 { group.addTask { try await auth.validAccessToken() } }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        #expect(tokens.count == 10)
        #expect(tokens.allSatisfy { $0 == "refreshed" })
        #expect(await endpoint.refreshCount == 1)
    }

    @Test("The in-flight task is released, so a later expiry refreshes again")
    func releasesInFlightTask() async throws {
        // Guards the `defer { refreshInFlight = nil }`. Without it the second
        // call would await the finished task and hand back the already-expired
        // token it produced, and the session would wedge — every request
        // carrying a stale token, and no refresh ever attempted again.
        let endpoint = StubTokenEndpoint(refreshResult: .success(.expired(refreshToken: "r2")))
        let store = EphemeralTokenStore(tokens: .expired())
        let auth = makeAuthenticator(endpoint: endpoint, store: store)

        _ = try await auth.validAccessToken()
        _ = try await auth.validAccessToken()

        #expect(await endpoint.refreshCount == 2)
        // The rotated token is used for the second attempt, not the original.
        #expect(await endpoint.lastRefreshToken == "r2")
    }

    @Test("A rejected grant ends the session and clears the tokens")
    func invalidGrantEndsSession() async throws {
        // Terminal, not transient: retrying cannot help, and leaving the dead
        // tokens on the device would make every later call fail the same way.
        let endpoint = StubTokenEndpoint(refreshResult: .failure(AuthError.sessionExpired))
        let store = EphemeralTokenStore(tokens: .expired())
        let auth = makeAuthenticator(endpoint: endpoint, store: store)

        await #expect(throws: AuthError.sessionExpired) { _ = try await auth.validAccessToken() }
        #expect(try await store.load() == nil)
    }

    @Test("With no session at all the caller is told to sign in")
    func noSession() async throws {
        let auth = makeAuthenticator(store: EphemeralTokenStore())
        await #expect(throws: AuthError.sessionExpired) { _ = try await auth.validAccessToken() }
    }

    @Test("A session with no refresh token cannot be refreshed")
    func missingRefreshToken() async throws {
        let store = EphemeralTokenStore(tokens: .expired(refreshToken: nil))
        let auth = makeAuthenticator(store: store)
        await #expect(throws: AuthError.sessionExpired) { _ = try await auth.validAccessToken() }
    }
}

@Suite("Sign in")
struct SignInTests {

    @Test("A completed hosted login exchanges the code and stores the tokens")
    func signInSucceeds() async throws {
        let endpoint = StubTokenEndpoint()
        let store = EphemeralTokenStore()
        // A box rather than a captured var: the closure is @Sendable, and the
        // compiler is right that mutating one across it is a race.
        let seenURL = Box<URL>()
        let browser = StubBrowser { url in
            seenURL.set(url)
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "state" }?.value ?? ""
            return URL(string: "com.tornotron.echno-ios://oauth/callback?code=abc&state=\(state)")!
        }
        let auth = makeAuthenticator(endpoint: endpoint, store: store, browser: browser)

        let tokens = try await auth.signIn()
        #expect(tokens.accessToken == "exchanged")
        #expect(await endpoint.exchangeCount == 1)
        #expect(try await store.load()?.accessToken == "exchanged")
        #expect(seenURL.value?.absoluteString.contains("code_challenge_method=S256") == true)
    }

    @Test("Dismissing the browser cancels without storing anything")
    func signInCancelled() async throws {
        let store = EphemeralTokenStore()
        let browser = StubBrowser { _ in throw AuthError.cancelled }
        let auth = makeAuthenticator(store: store, browser: browser)

        await #expect(throws: AuthError.cancelled) { _ = try await auth.signIn() }
        #expect(try await store.load() == nil)
    }

    @Test("A callback whose state does not match is refused")
    func signInStateMismatch() async throws {
        let store = EphemeralTokenStore()
        let browser = StubBrowser { _ in
            URL(string: "com.tornotron.echno-ios://oauth/callback?code=abc&state=forged")!
        }
        let auth = makeAuthenticator(store: store, browser: browser)

        await #expect(throws: AuthError.stateMismatch) { _ = try await auth.signIn() }
        #expect(try await store.load() == nil)
    }

    @Test("Each sign-in uses a fresh state")
    func freshStatePerAttempt() async throws {
        actor Seen { var states: Set<String> = []; func add(_ s: String) { states.insert(s) } }
        let seen = Seen()
        let browser = StubBrowser { url in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "state" }?.value ?? ""
            Task { await seen.add(state) }
            throw AuthError.cancelled
        }
        let auth = makeAuthenticator(browser: browser)

        _ = try? await auth.signIn()
        _ = try? await auth.signIn()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await seen.states.count == 2)
    }
}

@Suite("Sign out")
struct SignOutTests {

    @Test("Signing out ends the Keycloak session and clears the device")
    func signOut() async throws {
        let endpoint = StubTokenEndpoint()
        let store = EphemeralTokenStore(tokens: .stub())
        let auth = makeAuthenticator(endpoint: endpoint, store: store)

        try await auth.signOut()
        #expect(await endpoint.endSessionCount == 1)
        #expect(try await store.load() == nil)
    }

    @Test("Tokens are cleared even when ending the remote session fails")
    func clearsLocallyOnFailure() async throws {
        // Offline sign-out has to work. Leaving tokens on the device because a
        // network call failed would mean the app still looked signed in.
        let endpoint = StubTokenEndpoint()
        await endpoint.setEndSessionError(URLError(.notConnectedToInternet))
        let store = EphemeralTokenStore(tokens: .stub())
        let auth = makeAuthenticator(endpoint: endpoint, store: store)

        try await auth.signOut()
        #expect(try await store.load() == nil)
    }

    @Test("Signing out with no session is harmless")
    func signOutWithoutSession() async throws {
        let endpoint = StubTokenEndpoint()
        let auth = makeAuthenticator(endpoint: endpoint, store: EphemeralTokenStore())
        try await auth.signOut()
        #expect(await endpoint.endSessionCount == 0)
    }
}

/// An authenticator that answers from a script.
private actor StubAuthenticator: AuthenticationService {
    var token: Result<String, any Error> = .success("token-abc")
    private(set) var tokenRequests = 0

    func signIn() async throws -> TokenSet { .stub() }
    func signOut() async throws {}

    func validAccessToken() async throws -> String {
        tokenRequests += 1
        return try token.get()
    }

    func setToken(_ result: Result<String, any Error>) { token = result }
}

@Suite("Session credentials")
struct SessionCredentialsTests {

    @Test("The token comes from the authenticator, so refresh stays in one place")
    func forwardsToken() async throws {
        let authenticator = StubAuthenticator()
        let credentials = SessionCredentials(authenticator: authenticator)

        #expect(try await credentials.accessToken() == "token-abc")
        #expect(await authenticator.tokenRequests == 1)
    }

    @Test("An expired session propagates rather than yielding an empty token")
    func propagatesFailure() async {
        let authenticator = StubAuthenticator()
        await authenticator.setToken(.failure(AuthError.sessionExpired))
        let credentials = SessionCredentials(authenticator: authenticator)

        await #expect(throws: AuthError.sessionExpired) { _ = try await credentials.accessToken() }
    }

    @Test("There is no tenant until one is chosen")
    func noTenantBeforeSelection() async {
        let credentials = SessionCredentials(authenticator: StubAuthenticator())
        #expect(await credentials.currentOrganizationID() == nil)
    }

    @Test("Selecting an organization changes the tenant on later requests")
    func selectsTenant() async {
        let credentials = SessionCredentials(authenticator: StubAuthenticator())
        await credentials.select(organization: 42)
        #expect(await credentials.currentOrganizationID() == 42)
        await credentials.select(organization: nil)
        #expect(await credentials.currentOrganizationID() == nil)
    }
}
