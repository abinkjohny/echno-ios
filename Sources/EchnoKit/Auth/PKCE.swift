import CryptoKit
import Foundation

/// A Proof Key for Code Exchange pair (RFC 7636).
///
/// The iOS client is a **public** OAuth client: it ships no secret, so the
/// authorization code alone is not enough to prove the token request came from
/// this app. PKCE closes that. The app sends a hash of a secret it generated —
/// the challenge — with the authorization request, then the secret itself — the
/// verifier — with the token request. An attacker who intercepts the code on the
/// redirect cannot redeem it without the verifier, which never left the device.
public struct PKCE: Sendable, Equatable {

    /// The random secret. Sent only with the token request.
    public let verifier: String

    /// `BASE64URL(SHA256(verifier))`. Sent with the authorization request.
    public let challenge: String

    /// The only transform worth using. `plain` is permitted by the RFC and
    /// offers no protection at all, since the challenge would be the secret.
    public static let method = "S256"

    /// RFC 7636 §4.1 bounds. Shorter is guessable; longer is rejected outright.
    private static let allowedLength = 43...128

    /// The unreserved character set, so the verifier survives a round trip
    /// through a URL without encoding differing between the two requests.
    private static let alphabet = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Generates a fresh pair.
    ///
    /// A new verifier per sign-in attempt is the point: reusing one would let a
    /// code intercepted from an earlier attempt be redeemed against a later one.
    public init() {
        var generator = SystemRandomNumberGenerator()
        let verifier = String((0..<64).map { _ in
            Self.alphabet[Int(generator.next(upperBound: UInt64(Self.alphabet.count)))]
        })
        // Safe to force: the string was built from the allowed alphabet at a
        // length inside the permitted range.
        self = try! PKCE(verifier: verifier)
    }

    /// Builds a pair from a known verifier.
    ///
    /// - Parameter verifier: A 43–128 character unreserved string.
    /// - Throws: ``AuthError/invalidVerifier`` if it is outside the RFC bounds.
    public init(verifier: String) throws {
        guard Self.allowedLength.contains(verifier.count) else {
            throw AuthError.invalidVerifier
        }
        self.verifier = verifier
        self.challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension Data {
    /// base64url without padding, per RFC 7636 §A — `+` and `/` become `-` and
    /// `_`, and `=` is dropped, so the value is URL-safe unencoded.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
