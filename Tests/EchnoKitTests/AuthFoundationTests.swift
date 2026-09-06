import Foundation
import Testing
@testable import EchnoKit

@Suite("Keycloak configuration")
struct KeycloakConfigurationTests {

    private let configuration = KeycloakConfiguration(
        issuer: URL(string: "https://auth.echno.in/realms/echno-realm")!,
        clientID: "echno-ios",
        redirectURI: URL(string: "com.tornotron.echno-ios://oauth/callback")!
    )

    // A wrong path here does not fail loudly — it returns a Keycloak error page
    // that looks like a network problem. Pinning the exact URLs is cheap
    // insurance against a silent sign-in outage.
    @Test("Endpoints resolve to Keycloak's OIDC paths")
    func endpointPaths() {
        #expect(
            configuration.authorizationEndpoint.absoluteString
            == "https://auth.echno.in/realms/echno-realm/protocol/openid-connect/auth"
        )
        #expect(
            configuration.tokenEndpoint.absoluteString
            == "https://auth.echno.in/realms/echno-realm/protocol/openid-connect/token"
        )
        #expect(
            configuration.endSessionEndpoint.absoluteString
            == "https://auth.echno.in/realms/echno-realm/protocol/openid-connect/logout"
        )
    }

    @Test("The default scopes request an id token and a refresh token")
    func defaultScopes() {
        // `openid` is what makes this OIDC rather than bare OAuth, and without
        // `offline_access` Keycloak issues no refresh token, so the session
        // would die at the first access-token expiry.
        #expect(configuration.scopes.contains("openid"))
        #expect(configuration.scopes.contains("offline_access"))
    }

    @Test("The redirect URI uses the app's custom scheme")
    func redirectScheme() {
        // Must match the app's CFBundleURLSchemes and the client registration
        // in Keycloak, or the callback never returns to the app.
        #expect(configuration.redirectURI.scheme == "com.tornotron.echno-ios")
    }
}

@Suite("Token storage")
struct TokenStoreTests {

    private func tokens(expiringIn seconds: TimeInterval = 300) -> TokenSet {
        TokenSet(
            accessToken: "access",
            refreshToken: "refresh",
            idToken: "id",
            expiresAt: Date.now.addingTimeInterval(seconds)
        )
    }

    @Test("A saved token set is returned unchanged")
    func roundTrip() async throws {
        let store = EphemeralTokenStore()
        let saved = tokens()
        try await store.save(saved)
        #expect(try await store.load() == saved)
    }

    @Test("An empty store has nothing to load")
    func emptyStore() async throws {
        #expect(try await EphemeralTokenStore().load() == nil)
    }

    @Test("Clearing removes the session")
    func clear() async throws {
        let store = EphemeralTokenStore(tokens: tokens())
        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test("Saving replaces the previous set rather than accumulating")
    func saveReplaces() async throws {
        let store = EphemeralTokenStore(tokens: tokens())
        let rotated = TokenSet(
            accessToken: "rotated",
            refreshToken: "rotated-refresh",
            idToken: nil,
            expiresAt: Date.now.addingTimeInterval(600)
        )
        try await store.save(rotated)
        #expect(try await store.load()?.accessToken == "rotated")
    }

    @Test("A token already past its expiry is expired regardless of leeway")
    func pastExpiry() {
        let expired = TokenSet(
            accessToken: "a", refreshToken: nil, idToken: nil,
            expiresAt: Date.now.addingTimeInterval(-1)
        )
        #expect(expired.isExpired(leeway: 0))
    }
}

@Suite("Anonymous credentials")
struct AnonymousCredentialsTests {

    @Test("Requesting a token before sign-in fails as an auth error")
    func tokenThrows() async {
        // Modelled as 401 so the UI treats it as "sign in", not "network down".
        await #expect(throws: APIError.self) {
            _ = try await AnonymousCredentials().accessToken()
        }
    }

    @Test("There is no tenant before sign-in")
    func noOrganization() async {
        #expect(await AnonymousCredentials().currentOrganizationID() == nil)
    }
}

@Suite("Nested merge")
struct CacheMergeTests {

    /// A domain type with a nested collection the partial response omits —
    /// the exact shape that caused the vanishing-attachments bug on web.
    private struct Project: NestedMergeable, Equatable {
        struct Partial: Sendable {
            let name: String
        }

        let id: Int
        let name: String
        let attachments: [String]

        func merging(_ partial: Partial) -> Project {
            Project(id: id, name: partial.name, attachments: attachments)
        }
    }

    @Test("Merging a partial keeps nested collections the response omitted")
    func preservesNested() {
        let cached = Project(id: 1, name: "Old", attachments: ["a.pdf", "b.pdf"])
        let merged = Project.merge(cached, with: .init(name: "New"))
        #expect(merged?.name == "New")
        #expect(merged?.attachments == ["a.pdf", "b.pdf"])
    }

    @Test("Merging into an empty cache yields nothing, rather than a half-built value")
    func refusesToFabricate() {
        // A SimpleDto has no nested data, so building an entry from it alone
        // would cache a value whose collections are wrong. The caller refetches.
        #expect(Project.merge(nil, with: .init(name: "New")) == nil)
    }
}
