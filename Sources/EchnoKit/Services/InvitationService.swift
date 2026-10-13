import Foundation
import OpenAPIRuntime
import EchnoAPI

/// Redeems an organization invite code.
///
/// The one call a user who belongs to no organization can usefully make, and
/// the only route into an organization from the app: creating one is
/// `organization:admin`. Follows the shape ``UserService`` establishes — an
/// `actor`, a narrow endpoint protocol, domain types out, ``APIError`` for
/// every failure, bodies decoded by hand because the document declares `*/*`
/// (backend ask #19).
public actor InvitationService {

    private let client: any InvitationEndpoint

    public init(client: any InvitationEndpoint) {
        self.client = client
    }

    /// Redeems `code` for `userID` and answers the organization it granted.
    ///
    /// The caller supplies no organization id, and that is the point: the
    /// server resolves the organization from the code, so nothing has to be
    /// inferred across the tenant boundary from something a user typed.
    ///
    /// The employment details — department, designation, status — travel on the
    /// code from `InviteCodeGenerationDto`, set by whoever issued it. There is
    /// nothing for the app to collect.
    ///
    /// - Important: Succeeding here makes the held access token stale. Membership
    ///   is granted by adding the user to a Keycloak group, and the
    ///   `ORG_MEMBER_<id>` authority `TenantFilter` checks is a token claim, so
    ///   a token issued before this call cannot carry it. The caller must
    ///   renew — see ``KeycloakAuthenticator/renewAccessToken()``.
    ///
    /// - Throws: ``APIError``, with the status preserved so the caller can tell
    ///   a code that matches nothing from one that is no longer usable.
    public func join(using code: InviteCode, asUser userID: Int64) async throws -> Organization {
        let output: Operations.validateInviteCode.Output
        do {
            output = try await client.validateInviteCode(
                .init(path: .init(userId: userID), body: .json(.init(code: code.value)))
            )
        } catch {
            throw APIError.from(error)
        }

        switch output {
        case .ok(let response):
            guard case .any(let body) = response.body else {
                throw Self.failure(0, "The server confirmed the join in a form the app could not read.")
            }
            let dto = try await ResponseBody.decode(
                body,
                as: Components.Schemas.OrganizationDto.self
            )
            return try Organization(dto)

        // Not the same thing as a 400, and the reason both are spelled out.
        // `findByCode` throws `ResourceNotFoundException` before any validity
        // check runs, so a code that does not exist is a 404 while a code that
        // exists and cannot be used is a 400. To a user that is the difference
        // between a typo to correct and an invitation to ask for again.
        case .notFound:
            throw Self.failure(404, "That code does not match an invitation. Check the digits and try again.")
        case .badRequest:
            throw Self.failure(400, "That invitation can no longer be used. It may have expired or already been taken up. Ask for a new code.")

        // Reachable by an ordinary user, not a fault: the allowance is small
        // and a wrong code spends one of it. How long the wait is comes only in
        // `Retry-After`, which the document does not declare, so the generated
        // response carries no headers and there is no number to quote
        // (backend ask #21). Saying "shortly" is better than inventing one.
        case .tooManyRequests:
            throw Self.failure(429, "Too many attempts. Wait a little before trying another code.")

        case .forbidden:
            throw Self.failure(403, "You do not have permission to use this invitation.")
        case .code402:
            throw Self.failure(402, "That organization's subscription has lapsed. Its administrator will need to renew it.")
        case .conflict:
            throw Self.failure(409, "That invitation is being changed. Try again in a moment.")
        case .unprocessableContent:
            throw Self.failure(422, "That invitation could not be processed.")

        // Where "you already belong to this organization" lands, unfortunately.
        // `EmployeeService.joinOrganization` raises `IllegalStateException` for
        // an existing membership and nothing handles it, so the global handler
        // returns 500 (backend ask #22). The app cannot tell that apart from a
        // real fault without matching on the detail string, which would leak
        // server internals into the UI and break on any rewording, so the
        // message stays generic and the view prevents the likeliest cause by
        // not letting the button be pressed twice.
        case .internalServerError:
            throw Self.failure(500, "The join could not be completed. Try again shortly.")
        case .badGateway:
            throw Self.failure(502, "The server is unreachable. Try again shortly.")

        case .undocumented(let statusCode, _):
            if statusCode == 401 {
                throw Self.failure(401, "Your session has ended. Please sign in again.")
            }
            throw Self.failure(statusCode, "The server returned an unexpected status.")
        }
    }

    /// Logs the status and nothing else. The code is a credential for an
    /// organization, so it never reaches a log line.
    private static func failure(_ status: Int, _ message: String) -> APIError {
        Log.network.error("invite code redemption failed: \(status, privacy: .public)")
        return APIError(message: message, status: status)
    }
}
