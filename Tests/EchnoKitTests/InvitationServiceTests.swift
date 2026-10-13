import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import EchnoKit
import EchnoAPI

/// Implements only the one operation `InvitationService` calls.
private final class StubInvitationEndpoint: InvitationEndpoint, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _lastUserID: Int64?
    private var _lastCode: String?

    var result: @Sendable () throws -> Operations.validateInviteCode.Output

    init(
        result: @escaping @Sendable () throws -> Operations.validateInviteCode.Output
            = { .ok(.init(body: .any(HTTPBody(StubInvitationEndpoint.encoded(
                StubInvitationEndpoint.organization()
            ))))) }
    ) {
        self.result = result
    }

    static func organization(
        id: Int64 = 7,
        name: String? = "Tornotron Constructions"
    ) -> Components.Schemas.OrganizationDto {
        var dto = Components.Schemas.OrganizationDto()
        dto.id = id
        dto.organizationName = name
        return dto
    }

    /// The document declares `*/*`, so the generator emits a raw body and the
    /// stub has to encode the way the backend does.
    static func encoded(_ dto: Components.Schemas.OrganizationDto) -> Data {
        (try? JSONEncoder().encode(dto)) ?? Data()
    }

    var calls: Int { lock.withLock { _calls } }
    var lastUserID: Int64? { lock.withLock { _lastUserID } }
    var lastCode: String? { lock.withLock { _lastCode } }

    func validateInviteCode(
        _ input: Operations.validateInviteCode.Input
    ) async throws -> Operations.validateInviteCode.Output {
        lock.withLock {
            _calls += 1
            _lastUserID = input.path.userId
            if case .json(let dto) = input.body { _lastCode = dto.code }
        }
        return try result()
    }
}

@Suite("Invitation service")
struct InvitationServiceTests {

    private var code: InviteCode {
        get throws { try #require(InviteCode(String(repeating: "4", count: InviteCode.length))) }
    }

    @Test("A redeemed code answers with the organization that was joined")
    func redeemsAndMaps() async throws {
        let endpoint = StubInvitationEndpoint()
        let joined = try await InvitationService(client: endpoint).join(using: try code, asUser: 42)

        #expect(joined.name == "Tornotron Constructions")
        #expect(joined.id == 7)
        #expect(endpoint.lastUserID == 42)
    }

    /// The code reaches the body as typed. It is the whole credential, so a
    /// client that sent anything else would redeem the wrong organization or
    /// nothing at all.
    @Test("The code is sent exactly as validated")
    func sendsTheCode() async throws {
        let endpoint = StubInvitationEndpoint()
        let code = try code
        _ = try await InvitationService(client: endpoint).join(using: code, asUser: 42)
        #expect(endpoint.lastCode == code.value)
    }

    // A wrong code is a 404, not a 400: `findByCode` throws
    // `ResourceNotFoundException` before any of the validity checks run. The two
    // therefore mean different things to a user — "no such code" versus "this
    // code is no longer usable" — and telling them apart is the difference
    // between retyping and asking for a new invitation.
    @Test("A code that matches nothing says so")
    func unknownCode() async throws {
        let endpoint = StubInvitationEndpoint(result: { .notFound(.init(body: .any(HTTPBody()))) })
        let error = await #expect(throws: APIError.self) {
            try await InvitationService(client: endpoint).join(using: try self.code, asUser: 42)
        }
        #expect(error?.status == 404)
        #expect(error?.message.localizedCaseInsensitiveContains("code") == true)
    }

    @Test("An expired or spent code is distinguished from an unknown one")
    func unusableCode() async throws {
        let endpoint = StubInvitationEndpoint(result: { .badRequest(.init(body: .any(HTTPBody()))) })
        let error = await #expect(throws: APIError.self) {
            try await InvitationService(client: endpoint).join(using: try self.code, asUser: 42)
        }
        #expect(error?.status == 400)
        let unknown = try await Self.message(for: .notFound(.init(body: .any(HTTPBody()))))
        #expect(error?.message != unknown, "a spent code and an unknown code must not read alike")
    }

    /// The allowance is small and a wrong code costs one, so this is a state a
    /// real user reaches. It must not read as a server fault.
    @Test("A spent attempt allowance is reported as a wait, not a failure")
    func rateLimited() async throws {
        let endpoint = StubInvitationEndpoint(result: {
            .tooManyRequests(.init(body: .any(HTTPBody())))
        })
        let error = await #expect(throws: APIError.self) {
            try await InvitationService(client: endpoint).join(using: try self.code, asUser: 42)
        }
        #expect(error?.status == 429)
    }

    @Test(
        "Every other documented status carries its own explanation",
        arguments: [
            (402, "subscription"),
            (403, "permission"),
            (500, "could not"),
        ]
    )
    func documentedFailures(status: Int, fragment: String) async throws {
        let output: Operations.validateInviteCode.Output = switch status {
        case 402: .code402(.init(body: .any(HTTPBody())))
        case 403: .forbidden(.init(body: .any(HTTPBody())))
        default: .internalServerError(.init(body: .any(HTTPBody())))
        }
        let endpoint = StubInvitationEndpoint(result: { output })
        let error = await #expect(throws: APIError.self) {
            try await InvitationService(client: endpoint).join(using: try self.code, asUser: 42)
        }
        #expect(error?.status == status)
        #expect(error?.message.localizedCaseInsensitiveContains(fragment) == true)
    }

    /// 401 is not declared for this operation, so the generator emits no case
    /// for it and it arrives as `undocumented`. Left to the catch-all it would
    /// read as "unexpected status", which is the wrong advice for a session
    /// that has simply ended.
    @Test("An undeclared 401 is reported as an ended session")
    func undocumentedUnauthorized() async throws {
        let endpoint = StubInvitationEndpoint(result: {
            .undocumented(statusCode: 401, .init())
        })
        let error = await #expect(throws: APIError.self) {
            try await InvitationService(client: endpoint).join(using: try self.code, asUser: 42)
        }
        #expect(error?.status == 401)
        #expect(error?.message.localizedCaseInsensitiveContains("sign in") == true)
    }

    private static func message(
        for output: Operations.validateInviteCode.Output
    ) async throws -> String {
        let endpoint = StubInvitationEndpoint(result: { output })
        let code = try #require(InviteCode(String(repeating: "4", count: InviteCode.length)))
        let error = await #expect(throws: APIError.self) {
            try await InvitationService(client: endpoint).join(using: code, asUser: 42)
        }
        return error?.message ?? ""
    }
}
