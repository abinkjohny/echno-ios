import Foundation
import EchnoAPI

// Services depend on a narrow protocol naming only the operations they call,
// never on the whole generated `APIProtocol`.
//
// `APIProtocol` grows every time a tag is added to
// `openapi-generator-config.yaml`. If services took it directly, every test
// double would have to implement every operation in the document, and adding
// one module would break the tests of every other. Adding the `Users` tag broke
// the registration tests exactly that way, which is what prompted this.
//
// The generated `Client` already has all of these methods, so conformance is
// declaration-only. Tests implement one or two methods instead of hundreds.

/// The operations ``RegistrationService`` calls.
public protocol RegistrationEndpoint: Sendable {
    func registerUser(
        _ input: Operations.registerUser.Input
    ) async throws -> Operations.registerUser.Output
}

/// The operations ``UserService`` calls.
///
/// These are the `/web` variants deliberately. `GET /api/v1/user/web` is the
/// only current-user endpoint `TenantFilter` exempts from tenant scoping, so
/// the mobile twin `GET /api/v1/user` answers 400 for anyone who belongs to
/// more than one organization — see `backend-mobile-api-gaps.md` §2.
///
/// Note the generated names do not tell you which controller family an
/// operation belongs to: `readAllUsers` is web while `readAllUsers_1` is
/// mobile, yet `deleteAnUser` is mobile and `deleteAnUser_1` is web. The `_1`
/// suffix follows document order, not the `/web` split. `UserEndpointTests`
/// pins each one to its path so a regeneration cannot quietly swap them.
public protocol UserEndpoint: Sendable {
    func getCurrentUser(
        _ input: Operations.getCurrentUser.Input
    ) async throws -> Operations.getCurrentUser.Output

    func partialUpdateAUser_1(
        _ input: Operations.partialUpdateAUser_1.Input
    ) async throws -> Operations.partialUpdateAUser_1.Output

    func readAllOrganizationsForCurrentUser_1(
        _ input: Operations.readAllOrganizationsForCurrentUser_1.Input
    ) async throws -> Operations.readAllOrganizationsForCurrentUser_1.Output
}

extension Client: RegistrationEndpoint, UserEndpoint {}
