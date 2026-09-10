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

    static var credential: Credential? {
        if let token = value("ECHNO_SMOKE_ACCESS_TOKEN") { return .access(token) }
        if let token = value("ECHNO_SMOKE_REFRESH_TOKEN") { return .refresh(token) }
        if let user = value("ECHNO_SMOKE_USERNAME"), let password = value("ECHNO_SMOKE_PASSWORD") {
            return .password(username: user, password: password)
        }
        return nil
    }

    /// The suite runs only when it has a way to authenticate.
    static var isConfigured: Bool { credential != nil }

    static var server: ServerEnvironment {
        guard let raw = value("ECHNO_SMOKE_API_ORIGIN"), let url = URL(string: raw) else {
            return .production
        }
        return .custom(url)
    }

    static var keycloak: KeycloakConfiguration {
        KeycloakConfiguration(
            issuer: value("ECHNO_SMOKE_ISSUER").flatMap(URL.init(string:))
                ?? URL(string: "https://auth.echno.in/realms/echno-realm")!,
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
            let endpoint = URLSessionTokenEndpoint(configuration: keycloak)
            return try await endpoint.refresh(refreshToken: token).accessToken

        case .password(let username, let password):
            return try await directGrant(username: username, password: password)

        case nil:
            throw APIError(message: "No smoke credential configured", status: 0)
        }
    }

    /// Direct access grant, for a test-only Keycloak client.
    private static func directGrant(username: String, password: String) async throws -> String {
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
@Suite("Live backend smoke", .enabled(if: SmokeConfiguration.isConfigured), .serialized)
struct LiveSmokeTests {

    @Test("The signed-in user round-trips from the backend into a domain value")
    func currentUserRoundTrips() async throws {
        let token = try await SmokeConfiguration.accessToken()
        let client = EchnoClient.make(
            environment: SmokeConfiguration.server,
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
            environment: SmokeConfiguration.server,
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
        if let created = user.createdAt {
            #expect(created <= Date.now.addingTimeInterval(60))
            if let updated = user.updatedAt {
                #expect(created <= updated)
            }
        }
    }

}
