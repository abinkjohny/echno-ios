import Foundation
import Testing
@testable import EchnoKit
import EchnoAPI

// MARK: - Configuration

/// Where the smoke test points and how it authenticates, read from the
/// environment so no credential is ever written down in the repository.
///
/// Everything here is opt-in. With none of these variables set the suite is
/// skipped, which is what keeps `swift test` hermetic, offline and fast for the
/// other 200 tests — a suite that needs the network to pass is a suite people
/// stop running.
enum SmokeConfiguration {

    /// How the run gets a bearer token.
    ///
    /// Three ways in, because `echno-ios-client` deliberately allows none of
    /// the non-interactive OAuth grants — direct access grants and the device
    /// flow are both disabled on it, which is the right posture for a public
    /// PKCE client and not something to relax for a test's convenience.
    enum Credential {
        /// A token pasted from a signed-in session. Expires in minutes.
        case access(String)
        /// An `offline_access` refresh token, exchanged at the start of the run.
        /// Preferred: it lasts, and the exchange exercises the real refresh path.
        case refresh(String)
        /// Direct grant against a *separate* test client. Never the iOS client.
        case password(username: String, password: String)
    }

    static func value(_ key: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty else { return nil }
        return raw
    }

    /// Every variable that is a credential or part of one.
    ///
    /// Used to tell *nobody asked for this* from *someone asked and got it
    /// wrong*, which are the same thing to a `nil` credential and must not be
    /// the same thing to the suite — see ``isIntended``.
    private static let credentialKeys = [
        "ECHNO_SMOKE_ACCESS_TOKEN",
        "ECHNO_SMOKE_REFRESH_TOKEN",
        "ECHNO_SMOKE_USERNAME",
        "ECHNO_SMOKE_PASSWORD",
        "ECHNO_SMOKE_CLIENT_SECRET"
    ]

    static var credential: Credential? {
        if let token = value("ECHNO_SMOKE_ACCESS_TOKEN") { return .access(token) }
        if let token = value("ECHNO_SMOKE_REFRESH_TOKEN") { return .refresh(token) }
        if let user = value("ECHNO_SMOKE_USERNAME"), let password = value("ECHNO_SMOKE_PASSWORD") {
            return .password(username: user, password: password)
        }
        return nil
    }

    /// Whether anyone tried to configure this run.
    ///
    /// The suite is enabled by *intent*, not by a complete credential. A
    /// half-configured run — `ECHNO_SMOKE_USERNAME` with no password, say —
    /// must fail rather than skip: a skipped suite still prints
    /// `Test run with 2 tests in 1 suite passed`, which reads as though the
    /// smoke tests ran and were fine. Silence that looks like success is worse
    /// than a failure, and in a suite whose entire job is to catch what the
    /// hermetic tests cannot, it is the one outcome that must be impossible.
    static var isIntended: Bool {
        credentialKeys.contains { value($0) != nil }
    }

    /// Rejects a URL that would put a credential on the wire in cleartext.
    ///
    /// Loopback is allowed. Pointing at a local backend is the reason the
    /// override exists at all, and traffic that never leaves the machine cannot
    /// be read off the network — so a blanket HTTPS rule would break the
    /// primary use of the flag in the name of a threat it does not face.
    static func requireSecureTransport(_ url: URL, _ variable: String) throws -> URL {
        let scheme = url.scheme?.lowercased()
        if scheme == "https" { return url }
        if scheme == "http", isLoopback(url.host) { return url }
        throw APIError(
            message: """
                \(variable) must be https — \(scheme ?? "no scheme") would send a credential \
                in cleartext. http is allowed for loopback only.
                """,
            status: 0
        )
    }

    static func isLoopback(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if host == "::1" || host == "[::1]" { return true }

        // A full dotted quad in 127.0.0.0/8, not a host that merely starts
        // with one. `127.evil.com` and `127.0.0.1.evil.com` are ordinary names
        // that resolve wherever their owner points them, and a prefix test on
        // the host waves both through — which the tests for this caught.
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        let numbers = octets.compactMap { UInt8($0) }
        guard numbers.count == 4 else { return false }
        return numbers[0] == 127
    }

    /// Resolves an endpoint override, or the default when none is set.
    ///
    /// Unset falls back. **Set-but-unusable throws**, and the distinction is
    /// the whole point: a `guard let url = URL(string: raw) else { return
    /// fallback }` reads as a sensible default and is not one. The default for
    /// the API origin is production, so a space in a pasted URL — the commonest
    /// paste error there is — silently pointed the run at the live backend
    /// instead of the local one it was aimed at, and the issuer default would
    /// have sent a refresh token to production Keycloak. A set override is a
    /// statement of intent; failing to honour it quietly is not an option.
    static func resolveURL(_ raw: String?, _ variable: String, default fallback: URL) throws -> URL {
        guard let raw else { return fallback }
        guard let url = URL(string: raw) else {
            throw APIError(message: "\(variable) is not a URL: \(raw)", status: 0)
        }
        // `URL(string:)` is lenient: "https://" parses with no host at all, and
        // "backend.echno.in" parses as a relative path. Both would fail later,
        // somewhere less obvious than here.
        guard let host = url.host, !host.isEmpty else {
            throw APIError(message: "\(variable) has no host: \(raw)", status: 0)
        }
        return try requireSecureTransport(url, variable)
    }

    static func server() throws -> ServerEnvironment {
        let url = try resolveURL(
            value("ECHNO_SMOKE_API_ORIGIN"),
            "ECHNO_SMOKE_API_ORIGIN",
            default: ServerEnvironment.production.baseURL
        )
        return url == ServerEnvironment.production.baseURL ? .production : .custom(url)
    }

    static func keycloak() throws -> KeycloakConfiguration {
        let issuer = try resolveURL(
            value("ECHNO_SMOKE_ISSUER"),
            "ECHNO_SMOKE_ISSUER",
            default: URL(string: "https://auth.echno.in/realms/echno-realm")!
        )
        return KeycloakConfiguration(
            issuer: issuer,
            clientID: value("ECHNO_SMOKE_CLIENT_ID") ?? "echno-ios-client",
            redirectURI: URL(string: "com.tornotron.echno-ios://oauth/callback")!
        )
    }

    /// Sent as `X-Organization-Id`. Absent by default: the current-user lookup
    /// answers across every organization the caller belongs to, so it does not
    /// need one, and inventing a tenant id is precisely what `CLAUDE.md`
    /// forbids.
    static var organizationID: Int64? {
        value("ECHNO_SMOKE_ORGANIZATION_ID").flatMap(Int64.init)
    }

    /// Resolves whatever the environment supplied into a usable access token.
    static func accessToken() async throws -> String {
        switch credential {
        case .access(let token):
            return token

        case .refresh(let token):
            // The real endpoint, not a stand-in: this is the only place the
            // refresh path is exercised against a live Keycloak.
            let endpoint = URLSessionTokenEndpoint(configuration: try keycloak())
            return try await endpoint.refresh(refreshToken: token).accessToken

        case .password(let username, let password):
            return try await directGrant(username: username, password: password)

        case nil:
            // Reached only when `isIntended` let the suite run, so something
            // was set and it was not enough. Naming which is the difference
            // between a two-second fix and a puzzled half hour.
            let present = credentialKeys.filter { value($0) != nil }
            throw APIError(
                message: """
                    Smoke credentials are incomplete. Set \(present.joined(separator: ", ")) \
                    plus whatever it needs: a password grant needs both \
                    ECHNO_SMOKE_USERNAME and ECHNO_SMOKE_PASSWORD, or use \
                    ECHNO_SMOKE_REFRESH_TOKEN on its own.
                    """,
                status: 0
            )
        }
    }

    /// Direct access grant, for a test-only Keycloak client.
    private static func directGrant(username: String, password: String) async throws -> String {
        let keycloak = try keycloak()
        var request = URLRequest(url: keycloak.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormBody.encode([
            URLQueryItem(name: "grant_type", value: "password"),
            URLQueryItem(name: "client_id", value: keycloak.clientID),
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ] + (value("ECHNO_SMOKE_CLIENT_SECRET").map {
            [URLQueryItem(name: "client_secret", value: $0)]
        } ?? []))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // The body of a token failure names the reason (`unauthorized_client`
            // when the grant is not enabled for the client) and carries no
            // credential, so it is safe to surface and saves a guessing game.
            let reason = (try? JSONDecoder().decode(TokenErrorResponse.self, from: data))
                .map { "\($0.error): \($0.errorDescription ?? "")" } ?? "status \(status)"
            throw APIError(message: "Direct grant refused — \(reason)", status: status)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data).accessToken
    }
}

/// Presents an already-resolved token. The real ``SessionCredentials`` owns a
/// refresh loop and a keychain; neither belongs in a one-shot test process.
private struct SmokeCredentials: APICredentialProvider {
    let token: String
    let organizationID: Int64?

    func accessToken() async throws -> String { token }
    func currentOrganizationID() async -> Int64? { organizationID }
}

// MARK: - The suite

/// End-to-end checks against a running backend.
///
/// These exist because three real bugs — a doubled `/api/v1` prefix, a date
/// format the decoder rejected, and failures that named nothing — all reached a
/// device while 190 unit tests stayed green. Every one of them lived in the gap
/// between "the client is correct in isolation" and "the client and this
/// backend agree", which is the one thing a hermetic suite cannot see.
///
/// Run before merging anything that changes a URL, a DTO or the date handling:
///
/// ```sh
/// ECHNO_SMOKE_REFRESH_TOKEN=… swift test --filter LiveSmokeTests
/// ```
@Suite("Live backend smoke", .enabled(if: SmokeConfiguration.isIntended), .serialized)
struct LiveSmokeTests {

    @Test("The signed-in user round-trips from the backend into a domain value")
    func currentUserRoundTrips() async throws {
        let token = try await SmokeConfiguration.accessToken()
        let client = EchnoClient.make(
            environment: try SmokeConfiguration.server(),
            credentials: SmokeCredentials(
                token: token,
                organizationID: SmokeConfiguration.organizationID
            )
        )

        let user = try await UserService(client: client).currentUser()

        // Reaching here is most of the point: it means the request found a real
        // route, the response decoded — dates included, which is where this
        // broke — and every invariant `require(_:_:in:)` states held. The
        // assertions below name the invariants that would otherwise fail
        // silently as empty strings on screen.
        #expect(user.id > 0)
        #expect(!user.email.isEmpty)
        #expect(!user.name.isEmpty)
    }

    @Test("Live timestamps decode into a coherent ordering")
    func timestampsAreCoherent() async throws {
        let token = try await SmokeConfiguration.accessToken()
        let client = EchnoClient.make(
            environment: try SmokeConfiguration.server(),
            credentials: SmokeCredentials(
                token: token,
                organizationID: SmokeConfiguration.organizationID
            )
        )

        let user = try await UserService(client: client).currentUser()

        // The fraction on a LocalDateTime is split off and added back as an
        // interval, and a unit test can only prove that against a string this
        // file made up. Only a live run proves it against what the backend
        // actually emits — so this checks the decoded values relate to each
        // other and to now, rather than checking them against a constant that
        // would itself be the thing most likely to be wrong.
        // Required, not optional-checked. createdAt is an audit column the
        // backend always writes, so a nil is itself worth failing over — and an
        // `if let` here would let the whole assertion evaporate, leaving a test
        // that passes without checking the thing it exists to check.
        let created = try #require(user.createdAt, "the backend sent no createdAt")
        let tolerance = Date.now.addingTimeInterval(60)   // clock skew, not slack
        #expect(created <= tolerance)
        if let updated = user.updatedAt {
            #expect(created <= updated)
            // Bounding this too: an updatedAt in the future satisfies the
            // ordering above while still being nonsense.
            #expect(updated <= tolerance)
        }
    }

}

// MARK: - The harness's own guards

/// Always runs, credentials or not.
///
/// These are the checks that stop the smoke suite doing harm or lying about
/// its result, so they cannot themselves be gated behind the configuration
/// they are protecting.
@Suite("Smoke harness guards")
struct SmokeHarnessTests {

    private static let fallback = URL(string: "https://fallback.example.com")!

    @Test("No override falls back to the default")
    func unsetFallsBack() throws {
        #expect(try SmokeConfiguration.resolveURL(nil, "X", default: Self.fallback) == Self.fallback)
    }

    @Test(
        "A set but unusable override fails instead of falling back",
        arguments: [
            // A space in a pasted URL. URL(string:) returns nil, and the old
            // `else { return fallback }` sent the run — and its credential —
            // to production instead of the local backend it was aimed at.
            "http://exa mple.com",
            "ht!tp://localhost",
            "http://[oops",
            // Parses, but there is no host to connect to.
            "https://",
            // Parses as a relative path, not an origin.
            "backend.echno.in",
            "   "
        ]
    )
    func setButUnusableThrows(raw: String) {
        #expect(throws: APIError.self) {
            try SmokeConfiguration.resolveURL(raw, "ECHNO_SMOKE_API_ORIGIN", default: Self.fallback)
        }
    }

    @Test("A usable override is honoured, not quietly replaced")
    func usableOverrideHonoured() throws {
        let raw = "https://staging.echno.in"
        let resolved = try SmokeConfiguration.resolveURL(raw, "X", default: Self.fallback)
        #expect(resolved.absoluteString == raw)
    }

    @Test(
        "An https endpoint is accepted",
        arguments: ["https://backend.echno.in", "https://staging.echno.in/"]
    )
    func httpsAccepted(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(try SmokeConfiguration.requireSecureTransport(url, "X") == url)
    }

    @Test(
        "Cleartext is accepted for loopback, where nothing reaches the wire",
        arguments: [
            "http://localhost:8080",
            "http://127.0.0.1:8080",
            "http://127.1.2.3:8080",
            "http://[::1]:8080"
        ]
    )
    func loopbackAccepted(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(throws: Never.self) {
            try SmokeConfiguration.requireSecureTransport(url, "X")
        }
    }

    @Test(
        "Cleartext to anywhere else is refused before a credential is sent",
        arguments: [
            "http://backend.echno.in",
            "http://192.168.1.10:8080",
            // Hosts that merely begin like loopback and resolve anywhere at
            // all. A prefix test on the host would wave these through.
            "http://127.evil.com",
            "http://127.0.0.1.evil.com",
            "http://localhost.evil.com",
            "ws://backend.echno.in",
            "backend.echno.in"
        ]
    )
    func cleartextRefused(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(throws: APIError.self) {
            try SmokeConfiguration.requireSecureTransport(url, "ECHNO_SMOKE_API_ORIGIN")
        }
    }
}
