import Foundation
import EchnoAPI

/// Why a registration attempt failed, in terms the screen can present.
public enum RegistrationError: Error, Sendable, Equatable {
    /// The draft did not pass local validation. Carries the per-field messages.
    case invalidDraft([RegistrationField: String])
    /// The username or email is already taken.
    case accountExists
    /// The backend rejected the payload.
    case rejected(String)
    /// Anything else, including transport failures.
    case failed(String)
}

extension RegistrationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidDraft: "Some details still need fixing."
        case .accountExists: "An account with those details already exists."
        case .rejected(let reason): reason
        case .failed(let reason): reason
        }
    }
}

/// Creates accounts against `POST /api/v1/auth/register`.
///
/// The endpoint is `permitAll` on the backend and is the one operation this app
/// calls without a session — ``AuthenticationMiddleware`` exempts it by
/// `operationId` so no token is attached.
public struct RegistrationService: Sendable {

    private let client: any RegistrationEndpoint

    public init(client: any RegistrationEndpoint) {
        self.client = client
    }

    /// Registers a new account.
    ///
    /// - Parameter draft: The completed registration form.
    /// - Throws: ``RegistrationError``. Validation runs first, so an obviously
    ///   bad draft never reaches the network.
    public func register(_ draft: RegistrationDraft) async throws {
        let errors = draft.validate()
        guard errors.isEmpty else {
            throw RegistrationError.invalidDraft(errors)
        }

        let output: Operations.registerUser.Output
        do {
            output = try await client.registerUser(.init(body: .json(try Self.dto(from: draft))))
        } catch {
            throw RegistrationError.failed(APIError.from(error).message)
        }

        switch output {
        case .created:
            return
        case .conflict:
            throw RegistrationError.accountExists
        case .badRequest, .unprocessableContent:
            throw RegistrationError.rejected("Some of those details were not accepted.")
        case .forbidden:
            throw RegistrationError.rejected("Registration is not permitted for those details.")
        case .notFound:
            throw RegistrationError.failed("The registration service could not be reached.")
        case .undocumented(let statusCode, _):
            throw RegistrationError.failed("The registration service returned \(statusCode).")
        default:
            // The document declares 402, 500 and 502 as well. Naming them
            // individually would add nothing the user can act on.
            throw RegistrationError.failed("Registration could not be completed.")
        }
    }

    /// Maps the form draft onto the backend's `UserRegistrationDto`.
    ///
    /// `confirmPassword` is deliberately absent: it exists only to catch a typo
    /// on this device, and sending a second copy of the password would widen its
    /// exposure for no benefit. Enums are sent as their wire values, never their
    /// display labels.
    ///
    /// - Throws: ``RegistrationError/invalidDraft(_:)`` if a field the DTO
    ///   requires is absent. `validate()` already rules that out, so reaching it
    ///   means the two disagree — which is a bug worth an error that names the
    ///   field, not a force-unwrap that crashes in front of a user.
    static func dto(from draft: RegistrationDraft) throws -> Components.Schemas.UserRegistrationDto {
        guard let dateOfBirth = draft.dateOfBirth else {
            throw RegistrationError.invalidDraft([.dateOfBirth: "Date of birth is required"])
        }
        return .init(
            acceptTerms: draft.acceptTerms,
            dateOfBirth: dateOfBirth,
            email: draft.email,
            gender: draft.gender.rawValue,
            name: draft.name,
            password: draft.password,
            phone: draft.phone,
            role: draft.role?.rawValue,
            userName: draft.userName
        )
    }
}
