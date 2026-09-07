import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import EchnoKit
import EchnoAPI

/// Implements only the three operations `UserService` calls, which is the point
/// of the narrow endpoint protocols — adding a module's tag to the generator
/// config cannot break this.
private final class StubUserEndpoint: UserEndpoint, @unchecked Sendable {
    private let lock = NSLock()
    private var _currentUserCalls = 0

    var currentUserResult: @Sendable () throws -> Operations.getCurrentUser.Output

    init(
        currentUser: @escaping @Sendable () throws -> Operations.getCurrentUser.Output
            = { .ok(.init(body: .any(HTTPBody(StubUserEndpoint.encoded(StubUserEndpoint.user()))))) },
    ) {
        self.currentUserResult = currentUser
    }

    static func user(
        id: Int64 = 42,
        name: String = "Ravi Kumar",
        email: String = "ravi@echno.in"
    ) -> Components.Schemas.UserDto {
        var dto = Components.Schemas.UserDto()
        dto.id = id; dto.name = name; dto.email = email
        return dto
    }

    /// Responses are declared `*/*` in the document, so the generator emits raw
    /// bodies rather than typed JSON — the stub has to encode like the backend.
    static func encoded(_ dto: Components.Schemas.UserDto) -> Data {
        (try? JSONEncoder().encode(dto)) ?? Data()
    }

    var currentUserCalls: Int { lock.withLock { _currentUserCalls } }

    func getCurrentUser(
        _ input: Operations.getCurrentUser.Input
    ) async throws -> Operations.getCurrentUser.Output {
        lock.withLock { _currentUserCalls += 1 }
        return try currentUserResult()
    }

    func partialUpdateAUser_1(
        _ input: Operations.partialUpdateAUser_1.Input
    ) async throws -> Operations.partialUpdateAUser_1.Output {
        // Unreachable: the generated Input carries no body, so the operation
        // cannot send an update. Tracked as backend ask #20.
        .undocumented(statusCode: 501, .init())
    }

    func readAllOrganizationsForCurrentUser_1(
        _ input: Operations.readAllOrganizationsForCurrentUser_1.Input
    ) async throws -> Operations.readAllOrganizationsForCurrentUser_1.Output {
        .undocumented(statusCode: 501, .init())
    }
}

@Suite("User service")
struct UserServiceTests {

    @Test("The current user is fetched and mapped into the domain")
    func fetchesCurrentUser() async throws {
        let endpoint = StubUserEndpoint()
        let user = try await UserService(client: endpoint).currentUser()

        #expect(user.id == 42)
        #expect(user.name == "Ravi Kumar")
        #expect(endpoint.currentUserCalls == 1)
    }

    @Test("A DTO breaking an invariant surfaces as a mapping error, not a crash")
    func surfacesMappingFailure() async {
        let endpoint = StubUserEndpoint(currentUser: {
            var broken = Components.Schemas.UserDto()
            broken.name = "No id"
            return .ok(.init(body: .any(HTTPBody(StubUserEndpoint.encoded(broken)))))
        })
        await #expect(throws: MappingError.missing(field: "id", in: "UserDto")) {
            _ = try await UserService(client: endpoint).currentUser()
        }
    }

    @Test("A 401 is reported as an auth error the UI can act on")
    func mapsUnauthorized() async {
        let endpoint = StubUserEndpoint(currentUser: {
            .undocumented(statusCode: 401, .init())
        })
        await #expect(throws: APIError.self) {
            _ = try await UserService(client: endpoint).currentUser()
        }
    }

}
