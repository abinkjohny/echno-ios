import Foundation
import Testing
@testable import EchnoKit

@Suite("PKCE")
struct PKCETests {

    @Test("Challenge derivation matches the RFC 7636 test vector")
    func rfcTestVector() throws {
        // RFC 7636 Appendix B. If this fails, Keycloak will reject every code
        // exchange with invalid_grant and the message will not say why.
        let pkce = try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE.method == "S256")
    }

    @Test("A generated verifier is within the length the RFC allows")
    func verifierLength() {
        let verifier = PKCE().verifier
        #expect(verifier.count >= 43)
        #expect(verifier.count <= 128)
    }

    @Test("A generated verifier uses only unreserved characters")
    func verifierCharset() {
        // RFC 7636 §4.1: ALPHA / DIGIT / "-" / "." / "_" / "~". Anything else
        // has to be percent-encoded somewhere and will eventually be encoded
        // inconsistently between the authorize and token requests.
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let verifier = PKCE().verifier
        #expect(verifier.unicodeScalars.allSatisfy(allowed.contains))
    }

    @Test("The challenge is base64url with no padding")
    func challengeEncoding() {
        let challenge = PKCE().challenge
        #expect(!challenge.contains("="))
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
    }

    @Test("Each session gets a fresh verifier")
    func freshPerSession() {
        // Reusing a verifier across sign-ins would let an intercepted code from
        // one attempt be redeemed against another.
        #expect(PKCE().verifier != PKCE().verifier)
    }

    @Test("A verifier that is too short is rejected rather than silently used")
    func rejectsShortVerifier() {
        #expect(throws: AuthError.self) { try PKCE(verifier: "too-short") }
    }
}

@Suite("Authorization request")
struct AuthorizationRequestTests {

    private let configuration = KeycloakConfiguration(
        issuer: URL(string: "https://auth.echno.in/realms/echno-realm")!,
        clientID: "echno-ios",
        redirectURI: URL(string: "com.tornotron.echno-ios://oauth/callback")!
    )

    private func queryItems(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
    }

    @Test("The URL targets Keycloak's authorization endpoint")
    func endpoint() throws {
        let url = configuration.authorizationURL(pkce: PKCE(), state: "abc")
        #expect(url.absoluteString.hasPrefix(
            "https://auth.echno.in/realms/echno-realm/protocol/openid-connect/auth?"
        ))
    }

    @Test("Every parameter Keycloak needs for a public PKCE client is present")
    func parameters() throws {
        let pkce = try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let items = queryItems(configuration.authorizationURL(pkce: pkce, state: "state-123"))

        #expect(items["client_id"] == "echno-ios")
        #expect(items["redirect_uri"] == "com.tornotron.echno-ios://oauth/callback")
        #expect(items["response_type"] == "code")
        #expect(items["state"] == "state-123")
        #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["scope"]?.contains("openid") == true)
        #expect(items["scope"]?.contains("offline_access") == true)
    }

    @Test("The verifier itself never leaves the device")
    func verifierNotSent() throws {
        let pkce = try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = configuration.authorizationURL(pkce: pkce, state: "s")
        // Sending it would defeat the entire exchange — the challenge is the
        // only thing the authorization request is allowed to carry.
        #expect(!url.absoluteString.contains(pkce.verifier))
    }
}

@Suite("Authorization callback")
struct AuthorizationCallbackTests {

    private let redirect = URL(string: "com.tornotron.echno-ios://oauth/callback")!

    @Test("A successful callback yields the authorization code")
    func success() throws {
        let url = URL(string: "com.tornotron.echno-ios://oauth/callback?code=abc123&state=xyz")!
        #expect(try AuthorizationCallback.code(from: url, expectedState: "xyz") == "abc123")
    }

    @Test("A mismatched state is rejected")
    func stateMismatch() {
        // The state is the CSRF defence: accepting a callback whose state we did
        // not issue would let an attacker inject their own authorization code.
        let url = URL(string: "com.tornotron.echno-ios://oauth/callback?code=abc&state=attacker")!
        #expect(throws: AuthError.self) {
            try AuthorizationCallback.code(from: url, expectedState: "xyz")
        }
    }

    @Test("A missing state is rejected, not treated as a match")
    func stateMissing() {
        let url = URL(string: "com.tornotron.echno-ios://oauth/callback?code=abc")!
        #expect(throws: AuthError.self) {
            try AuthorizationCallback.code(from: url, expectedState: "xyz")
        }
    }

    @Test("A provider error is surfaced with its description")
    func providerError() {
        let url = URL(string:
            "com.tornotron.echno-ios://oauth/callback?error=access_denied&error_description=User%20said%20no&state=xyz")!
        #expect(throws: AuthError.provider("User said no")) {
            try AuthorizationCallback.code(from: url, expectedState: "xyz")
        }
    }

    @Test("An error without a description still names the error code")
    func providerErrorWithoutDescription() {
        let url = URL(string: "com.tornotron.echno-ios://oauth/callback?error=invalid_request&state=xyz")!
        #expect(throws: AuthError.provider("invalid_request")) {
            try AuthorizationCallback.code(from: url, expectedState: "xyz")
        }
    }

    @Test("A callback with neither code nor error is rejected")
    func emptyCallback() {
        let url = URL(string: "com.tornotron.echno-ios://oauth/callback?state=xyz")!
        #expect(throws: AuthError.self) {
            try AuthorizationCallback.code(from: url, expectedState: "xyz")
        }
    }
}
