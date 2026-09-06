import Foundation
import Testing
@testable import EchnoKit

private let configuration = KeycloakConfiguration(
    issuer: URL(string: "https://auth.echno.in/realms/echno-realm")!,
    clientID: "echno-ios-client",
    redirectURI: URL(string: "com.tornotron.echno-ios://oauth/callback")!
)

private func form(_ items: [URLQueryItem]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

@Suite("Token request bodies")
struct TokenRequestTests {

    @Test("The code exchange carries the verifier and no client secret")
    func exchange() {
        let items = form(configuration.tokenExchangeForm(code: "abc", verifier: "v-123"))
        #expect(items["grant_type"] == "authorization_code")
        #expect(items["code"] == "abc")
        #expect(items["code_verifier"] == "v-123")
        #expect(items["client_id"] == "echno-ios-client")
        #expect(items["redirect_uri"] == "com.tornotron.echno-ios://oauth/callback")
        // A public client has no secret. Sending one would mean we had shipped
        // one, which is the thing PKCE exists to avoid.
        #expect(items["client_secret"] == nil)
    }

    @Test("A refresh names the refresh grant and the client")
    func refresh() {
        let items = form(configuration.refreshForm(refreshToken: "r-123"))
        #expect(items["grant_type"] == "refresh_token")
        #expect(items["refresh_token"] == "r-123")
        #expect(items["client_id"] == "echno-ios-client")
    }

    @Test("Ending the session sends the refresh token so Keycloak can revoke it")
    func logout() {
        // Dropping local tokens is not a sign-out: without this the session
        // stays live at the identity provider and SSO would sign the next
        // person straight back in.
        let items = form(configuration.endSessionForm(refreshToken: "r-123"))
        #expect(items["refresh_token"] == "r-123")
        #expect(items["client_id"] == "echno-ios-client")
    }

    @Test("Bodies encode as form data with reserved characters escaped")
    func encoding() {
        let body = FormBody.encode([
            URLQueryItem(name: "redirect_uri", value: "com.tornotron.echno-ios://oauth/callback"),
            URLQueryItem(name: "scope", value: "openid offline_access")
        ])
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("redirect_uri=com.tornotron.echno-ios%3A%2F%2Foauth%2Fcallback"))
        // A raw space here would produce a malformed body Keycloak rejects.
        #expect(text.contains("scope=openid%20offline_access"))
        #expect(!text.contains(" "))
    }
}

@Suite("Token response")
struct TokenResponseTests {

    private let json = Data("""
    {
      "access_token": "access-abc",
      "refresh_token": "refresh-abc",
      "id_token": "id-abc",
      "expires_in": 300,
      "token_type": "Bearer",
      "scope": "openid profile"
    }
    """.utf8)

    @Test("Keycloak's snake_case response decodes")
    func decodes() throws {
        let response = try JSONDecoder().decode(TokenResponse.self, from: json)
        #expect(response.accessToken == "access-abc")
        #expect(response.refreshToken == "refresh-abc")
        #expect(response.idToken == "id-abc")
        #expect(response.expiresIn == 300)
    }

    @Test("expires_in becomes an absolute expiry")
    func absoluteExpiry() throws {
        let issued = Date(timeIntervalSince1970: 1_000_000)
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: json).tokenSet(issuedAt: issued)
        #expect(tokens.expiresAt == issued.addingTimeInterval(300))
        #expect(tokens.accessToken == "access-abc")
    }

    @Test("A refresh that omits a new refresh token keeps the previous one")
    func retainsRefreshToken() throws {
        // Keycloak omits refresh_token when rotation is off. Treating that as
        // "no refresh token" would end the session on the next expiry.
        let withoutRefresh = Data(#"{"access_token":"a","expires_in":60}"#.utf8)
        let response = try JSONDecoder().decode(TokenResponse.self, from: withoutRefresh)
        let tokens = response.tokenSet(issuedAt: .now, fallbackRefreshToken: "previous")
        #expect(tokens.refreshToken == "previous")
    }

    @Test("A rotated refresh token replaces the previous one")
    func prefersRotatedToken() throws {
        let response = try JSONDecoder().decode(TokenResponse.self, from: json)
        let tokens = response.tokenSet(issuedAt: .now, fallbackRefreshToken: "previous")
        #expect(tokens.refreshToken == "refresh-abc")
    }

    @Test("An error response from the token endpoint decodes to its reason")
    func errorResponse() throws {
        let json = Data(#"{"error":"invalid_grant","error_description":"Token is not active"}"#.utf8)
        let failure = try JSONDecoder().decode(TokenErrorResponse.self, from: json)
        #expect(failure.error == "invalid_grant")
        #expect(failure.isInvalidGrant)
        #expect(failure.errorDescription == "Token is not active")
    }
}

@Suite("Token endpoint failures")
struct TokenEndpointFailureTests {

    @Test("invalid_grant is classified as the session ending")
    func invalidGrantIsTerminal() {
        let body = Data(#"{"error":"invalid_grant","error_description":"Token is not active"}"#.utf8)
        let error = URLSessionTokenEndpoint.failure(from: body, status: 400)
        #expect(error as? AuthError == .sessionExpired)
    }

    @Test("Other OAuth errors keep their description and do not end the session")
    func otherErrorsArePassedThrough() {
        // A misconfigured client must not read as "your session expired", or the
        // user is sent round a sign-in loop that cannot succeed.
        let body = Data(#"{"error":"invalid_client","error_description":"Client not found"}"#.utf8)
        let error = URLSessionTokenEndpoint.failure(from: body, status: 401)
        #expect(error as? AuthError == .provider("Client not found"))
    }

    @Test("A non-JSON failure still names the status")
    func unparseableFailure() {
        let error = URLSessionTokenEndpoint.failure(from: Data("<html>502</html>".utf8), status: 502)
        #expect(error as? AuthError == .provider("Sign-in service returned 502."))
    }
}
