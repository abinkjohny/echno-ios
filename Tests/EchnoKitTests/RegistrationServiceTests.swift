import Foundation
import OpenAPIRuntime
import Testing
@testable import EchnoKit
import EchnoAPI

/// Records the request and answers with a scripted output.
///
/// Conforms to `RegistrationEndpoint`, not `APIProtocol` — one method instead
/// of every operation in the document, so adding a module's tag to the
/// generator config cannot break this test.
private final class StubAPI: RegistrationEndpoint, @unchecked Sendable {
    private let lock = NSLock()
    private var received: Operations.registerUser.Input?
    private let output: @Sendable () throws -> Operations.registerUser.Output

    init(output: @escaping @Sendable () throws -> Operations.registerUser.Output) {
        self.output = output
    }

    var lastInput: Operations.registerUser.Input? {
        lock.withLock { received }
    }

    func registerUser(
        _ input: Operations.registerUser.Input
    ) async throws -> Operations.registerUser.Output {
        // withLock rather than lock()/unlock(): the latter is unavailable from
        // an async context, because a suspension while holding it would deadlock.
        lock.withLock { received = input }
        return try output()
    }
}

private func validDraft() -> RegistrationDraft {
    RegistrationDraft(
        userName: "john_doe",
        name: "John Doe",
        email: "john@company.com",
        password: "Str0ng!pass",
        confirmPassword: "Str0ng!pass",
        phone: "+911234567890",
        gender: .female,
        dateOfBirth: Date(timeIntervalSince1970: 0),
        role: .hrManager,
        acceptTerms: true
    )
}

@Suite("Registration service")
struct RegistrationServiceTests {

    @Test("The draft maps onto the backend's registration DTO")
    func mapsDraft() async throws {
        let api = StubAPI { .created(.init(body: .any(HTTPBody("{}")))) }
        try await RegistrationService(client: api).register(validDraft())

        let input = try #require(api.lastInput)
        guard case .json(let dto) = input.body else {
            Issue.record("expected a JSON body"); return
        }
        #expect(dto.userName == "john_doe")
        #expect(dto.name == "John Doe")
        #expect(dto.email == "john@company.com")
        #expect(dto.password == "Str0ng!pass")
        #expect(dto.phone == "+911234567890")
        // Wire values, not display labels — the backend parses these.
        #expect(dto.gender == "Female")
        #expect(dto.role == "HR_MANAGER")
        #expect(dto.dateOfBirth == Date(timeIntervalSince1970: 0))
        #expect(dto.acceptTerms == true)
    }

    @Test("The confirmation field is never sent")
    func doesNotSendConfirmation() async throws {
        // It exists only to catch typing mistakes on this device. Sending a
        // second copy of the password widens the exposure for no benefit.
        let api = StubAPI { .created(.init(body: .any(HTTPBody("{}")))) }
        try await RegistrationService(client: api).register(validDraft())
        guard case .json(let dto) = try #require(api.lastInput).body else { return }
        let encoded = try JSONEncoder().encode(dto)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("confirmPassword"))
    }

    @Test("An invalid draft is refused before any request is made")
    func validatesBeforeSending() async {
        // The server validates too, but a round trip to be told the email is
        // malformed is a slow way to learn it, and it creates load for nothing.
        let api = StubAPI { .created(.init(body: .any(HTTPBody("{}")))) }
        var draft = validDraft()
        draft.email = "nonsense"

        await #expect(throws: RegistrationError.self) {
            try await RegistrationService(client: api).register(draft)
        }
        #expect(api.lastInput == nil)
    }

    @Test("A conflict is reported as the account already existing")
    func conflict() async {
        let api = StubAPI { .conflict(.init(body: .any(HTTPBody("{}")))) }
        await #expect(throws: RegistrationError.accountExists) {
            try await RegistrationService(client: api).register(validDraft())
        }
    }

    @Test("A rejected payload is reported as a validation failure")
    func badRequest() async {
        let api = StubAPI { .badRequest(.init(body: .any(HTTPBody("{}")))) }
        await #expect(throws: RegistrationError.self) {
            try await RegistrationService(client: api).register(validDraft())
        }
    }

    @Test("An unexpected status is surfaced rather than swallowed")
    func undocumented() async {
        let api = StubAPI { .undocumented(statusCode: 500, .init()) }
        await #expect(throws: RegistrationError.self) {
            try await RegistrationService(client: api).register(validDraft())
        }
    }
}
