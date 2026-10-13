import Foundation
import OpenAPIRuntime
import EchnoAPI

/// Reads the organizations the signed-in user belongs to.
///
/// Follows the shape ``UserService`` establishes: an `actor`, a narrow endpoint
/// protocol, domain types out, `APIError` for every failure. Responses are
/// decoded by hand for the same reason — the document declares `*/*`, so the
/// generator emits a raw body (backend ask #19).
public actor OrganizationService {

    private let client: any OrganizationEndpoint

    public init(client: any OrganizationEndpoint) {
        self.client = client
    }

    /// Every organization `userID` is a member of.
    ///
    /// This is the multi-org bootstrap: until it answers, the app has no
    /// legitimate value for `X-Organization-Id` and must not invent one.
    ///
    /// - Throws: ``APIError``, with the status preserved so a failure can be
    ///   told apart from an empty membership list.
    public func organizations(forUser userID: Int64) async throws -> [Organization] {
        let output: Operations.readAllOrganizationsForCurrentUser_1.Output
        do {
            output = try await client.readAllOrganizationsForCurrentUser_1(
                .init(path: .init(userId: userID))
            )
        } catch {
            throw APIError.from(error)
        }

        switch output {
        case .ok(let response):
            guard case .any(let body) = response.body else {
                throw Self.failure(0, "The server listed your organizations in a form the app could not read.")
            }
            let dtos = try await ResponseBody.decode(
                body,
                as: [Components.Schemas.OrganizationDto].self
            )
            // Mapped eagerly, so one malformed row fails the call. Skipping it
            // would be kinder to the list and wrong: this list *is* the tenant
            // switcher, and someone shown one organization when they belong to
            // two will act in the wrong tenant believing they had no choice.
            return try dtos.map(Organization.init)

        case .forbidden:
            throw Self.failure(403, "Your account does not have access to these organizations.")
        case .notFound:
            throw Self.failure(404, "No organizations exist for this account.")
        case .badRequest:
            throw Self.failure(400, "The request for your organizations was rejected.")
        case .conflict:
            throw Self.failure(409, "Your organization memberships are being changed. Try again.")
        case .unprocessableContent:
            throw Self.failure(422, "The request for your organizations could not be processed.")
        case .internalServerError:
            throw Self.failure(500, "The server could not list your organizations.")
        case .badGateway:
            throw Self.failure(502, "The server is unreachable. Try again shortly.")

        // Generated as `code402`, not `paymentRequired` — the generator names a
        // status it has no vocabulary for by its number. Easy to miss when
        // scanning the Output for a word, and the reason this is a named case
        // rather than something the catch-all absorbs.
        case .code402:
            throw Self.failure(402, "This organization's subscription has lapsed.")

        case .undocumented(let statusCode, _):
            // 401 is the one that matters here. The document does not declare
            // it for this operation, so the generator emits no case, and an
            // expired session is the likeliest failure on a call the app makes
            // at launch. Left to the catch-all it would read as "unexpected
            // status 401" — the commonest failure, described the least usefully.
            if statusCode == 401 {
                throw Self.failure(401, "Your session has ended. Please sign in again.")
            }
            throw Self.failure(statusCode, "The server returned an unexpected status.")
        }
    }

    private static func failure(_ status: Int, _ message: String) -> APIError {
        Log.network.error("organizations failed: \(status, privacy: .public)")
        return APIError(message: message, status: status)
    }
}
