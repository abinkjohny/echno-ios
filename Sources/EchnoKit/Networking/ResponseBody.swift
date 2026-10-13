import Foundation
import OpenAPIRuntime

/// Reads a raw response body into a generated schema.
///
/// Every service needs this because the backend declares its response content
/// as `*/*` rather than `application/json`: `swift-openapi-generator` cannot
/// produce a typed body from that, so 129 of the 133 generated response bodies
/// arrive as raw `HTTPBody`. The schemas are still generated and typed, so the
/// work is to collect the bytes and decode them. Tracked as backend ask #19 —
/// when responses are declared `application/json` this disappears and the
/// services use `response.body.json`.
///
/// It lives here rather than on a service because the second service to need it
/// would otherwise borrow it from the first, and a module reaching into another
/// module's internals for a decoder is how layers stop meaning anything.
public enum ResponseBody {

    /// Collects a body and decodes it, capped so a malformed or hostile
    /// response cannot be read into memory without bound.
    ///
    /// Uses ``JSONDecoder/echno``, so the four date shapes the backend emits are
    /// handled the same way everywhere.
    ///
    /// - Throws: ``APIError/decoding()``, which deliberately carries no detail:
    ///   its message reaches the user through `LocalizedError`, and a
    ///   `DecodingError` names the coding path and — for a date — the value that
    ///   would not parse, so a malformed `dateOfBirth` would put the user's date
    ///   of birth on screen. The diagnostic goes to `Log.network` instead.
    public static func decode<T: Decodable>(
        _ body: HTTPBody,
        as type: T.Type = T.self
    ) async throws -> T {
        let data: Data
        do {
            data = try await Data(collecting: body, upTo: 8 << 20)
        } catch {
            Log.network.error(
                "Could not read the response body: \(String(describing: error), privacy: .public)"
            )
            throw APIError.decoding()
        }
        do {
            return try JSONDecoder.echno.decode(T.self, from: data)
        } catch {
            // One literal, not two concatenated: an os_log message is built by
            // a result builder and cannot be assembled with `+`.
            Log.network.error("Could not decode \(String(describing: T.self), privacy: .public): \(String(describing: error), privacy: .public)")
            throw APIError.decoding()
        }
    }
}
