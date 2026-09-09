import Foundation
import OpenAPIRuntime
import EchnoAPI

/// Reads the signed-in user.
///
/// ## The convention this file establishes
///
/// - **An `actor`**, so concurrent callers cannot interleave on shared state.
/// - **Takes a narrow endpoint protocol**, never the generated `APIProtocol`,
///   so a test double implements a handful of methods rather than every
///   operation in the document.
/// - **Returns domain types only.** No `Components.Schemas.*` escapes; mapping
///   failures name the DTO and the field.
/// - **Maps transport and status failures onto ``APIError``**, so callers have
///   one error type to switch on.
///
/// ## Why responses are decoded by hand
///
/// The backend declares response content as `*/*` rather than
/// `application/json`. `swift-openapi-generator` cannot produce a typed body
/// from that, so 129 of the 133 generated response bodies are raw
/// `HTTPBody` — including every one here. The schemas themselves are still
/// generated and typed, so the work is to decode the bytes into
/// `Components.Schemas.UserDto` and map from there. Tracked as backend ask #19;
/// when responses are declared `application/json` these decodes collapse into
/// `response.body.json`.
public actor UserService {

    private let client: any UserEndpoint

    public init(client: any UserEndpoint) {
        self.client = client
    }

    /// The signed-in user.
    ///
    /// Calls `GET /api/v1/user/web`, which `TenantFilter` exempts from tenant
    /// scoping. The mobile twin `GET /api/v1/user` is not exempt and answers
    /// 400 for anyone belonging to more than one organization — which is every
    /// bootstrap. See `backend-mobile-api-gaps.md` §2.
    public func currentUser() async throws -> User {
        let output: Operations.getCurrentUser.Output
        do {
            output = try await client.getCurrentUser(.init())
        } catch {
            throw APIError.from(error)
        }

        switch output {
        case .ok(let response):
            guard case .any(let body) = response.body else {
                throw Self.failure(0, "The server sent a profile in a form the app could not read.")
            }
            return try User(await Self.decode(body))

        // Every status the document declares is named. Collapsing them into one
        // message is how "Could not load your profile" ends up on screen with
        // nothing — not a log line, not a status code — to say whether the
        // server was down, the account lacks access, or the record is missing.
        case .unauthorized:
            throw Self.failure(401, "Your session has ended. Please sign in again.")
        case .forbidden:
            // The likeliest cause on a fresh Keycloak client: the access token
            // carries no `groups` claim, so the backend can derive no
            // organization membership and refuses. See keycloak-setup.md §4.
            throw Self.failure(403, "Your account does not have access to this profile.")
        case .notFound:
            throw Self.failure(404, "No profile exists for this account.")
        case .badRequest:
            throw Self.failure(400, "The profile request was rejected.")
        case .conflict:
            throw Self.failure(409, "The profile could not be read right now.")
        case .unprocessableContent:
            throw Self.failure(422, "The profile request was rejected.")
        case .code402:
            throw Self.failure(402, "This organization's subscription does not cover that.")
        case .internalServerError:
            throw Self.failure(500, "The server had a problem. Try again shortly.")
        case .badGateway:
            throw Self.failure(502, "The server is unreachable. Try again shortly.")
        case .undocumented(let statusCode, _):
            throw Self.failure(statusCode, HTTPURLResponse.localizedString(forStatusCode: statusCode))
        }
    }

    /// Builds the error and records it.
    ///
    /// The log line is the point. Without it a failure reaching the user is
    /// undiagnosable — the screen says something went wrong and nothing anywhere
    /// says what. Carries no response body, which could hold profile data.
    private static func failure(_ status: Int, _ message: String) -> APIError {
        Log.network.error("getCurrentUser failed: \(status, privacy: .public) — \(message, privacy: .public)")
        return APIError(message: message, status: status)
    }

    /// Collects a raw response body and decodes it into a generated schema.
    ///
    /// Uses ``JSONDecoder/echno``, so the four date shapes the backend emits are
    /// handled the same way here as everywhere else.
    static func decode<T: Decodable>(
        _ body: HTTPBody,
        as type: T.Type = T.self
    ) async throws -> T {
        let data: Data
        do {
            data = try await Data(collecting: body, upTo: 8 << 20)
        } catch {
            throw APIError.decoding("Could not read the response body: \(error)")
        }
        do {
            return try JSONDecoder.echno.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("Could not decode \(T.self): \(error)")
        }
    }
}

// MARK: - Updating a profile
//
// Deliberately not implemented. `PATCH /api/v1/user/web/{id}` takes a
// multipart body, and the document describes it in a way the generator cannot
// model: `Operations.partialUpdateAUser_1.Input` has no `body` property at all,
// so calling the generated operation would send an empty request and silently
// change nothing.
//
// This is not something the client can work around by encoding more carefully —
// the capability is absent from the generated surface. It needs the backend to
// declare the multipart body so it can be modelled. Tracked as ask #20 in
// `local-docs/backend-mobile-api-gaps.md`.
//
// The store's replace-on-full-Dto rule is exercised directly in the meantime,
// since that discipline is about caching and does not depend on the request
// shape.
