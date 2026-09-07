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

extension Client: RegistrationEndpoint {}
