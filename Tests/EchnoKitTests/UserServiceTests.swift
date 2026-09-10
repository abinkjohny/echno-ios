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

    @Test("Each declared status keeps its code, so a failure can be diagnosed")
    func statusesArePreserved() async throws {
        // The whole set used to collapse into one message with status 0. A
        // screen then said "Could not load your profile" whether the server was
        // down, the account lacked access, or the record did not exist — and
        // nothing anywhere said which.
        let cases: [(Operations.getCurrentUser.Output, Int)] = [
            (.unauthorized(.init(body: .any(HTTPBody("")))), 401),
            (.forbidden(.init(body: .any(HTTPBody("")))), 403),
            (.notFound(.init(body: .any(HTTPBody("")))), 404),
            (.badRequest(.init(body: .any(HTTPBody("")))), 400),
            (.internalServerError(.init(body: .any(HTTPBody("")))), 500),
            (.badGateway(.init(body: .any(HTTPBody("")))), 502),
            (.undocumented(statusCode: 418, .init()), 418)
        ]

        for (output, expected) in cases {
            let endpoint = StubUserEndpoint(currentUser: { output })
            await #expect(throws: APIError.self) {
                _ = try await UserService(client: endpoint).currentUser()
            }
            do {
                _ = try await UserService(client: endpoint).currentUser()
            } catch let error as APIError {
                #expect(error.status == expected)
                #expect(!error.message.isEmpty)
            }
        }
    }

    @Test("A 500's ProblemDetail reaches the log but not the user")
    func serverErrorDetailIsLoggedNotShown() async {
        // The backend's catch-all puts the real cause in `detail`. It belongs in
        // the log, where whoever is debugging can read it — and not on screen,
        // because a 500's detail is an exception message.
        let problem = #"{"title":"Internal Server Error","detail":"An unexpected error occurred: boom","status":500}"#
        let endpoint = StubUserEndpoint(currentUser: {
            .internalServerError(.init(body: .any(HTTPBody(problem))))
        })

        do {
            _ = try await UserService(client: endpoint).currentUser()
            Issue.record("expected a failure")
        } catch let error as APIError {
            #expect(error.status == 500)
            #expect(error.message == "The server had a problem. Try again shortly.")
            #expect(!error.message.contains("boom"))
        } catch {
            Issue.record("expected an APIError")
        }
    }

    @Test("A 500 with an unreadable body still fails cleanly")
    func serverErrorWithGarbageBody() async {
        let endpoint = StubUserEndpoint(currentUser: {
            .internalServerError(.init(body: .any(HTTPBody("<html>502 Bad Gateway</html>"))))
        })
        do {
            _ = try await UserService(client: endpoint).currentUser()
            Issue.record("expected a failure")
        } catch let error as APIError {
            #expect(error.status == 500)
        } catch {
            Issue.record("expected an APIError")
        }
    }

    @Test("A body that will not decode keeps its contents out of the message")
    func decodingFailureDoesNotLeakTheBody() async throws {
        // A date the parser rejects, so the failure lands in the date decoder —
        // the one path whose DecodingError quotes the offending value back.
        // dateOfBirth is the field precisely because it is PII: whatever the
        // message carries is what a user would see on screen and paste into a
        // support ticket.
        let birthday = "1987-03-14-UNPARSEABLE"
        let json = #"{"id":1,"email":"person@example.com","dateOfBirth":"\#(birthday)"}"#
        do {
            _ = try await UserService.decode(
                HTTPBody(Data(json.utf8)),
                as: Components.Schemas.UserDto.self
            )
            Issue.record("expected the decode to fail")
        } catch let error as APIError {
            #expect(!error.message.contains(birthday))
            #expect(!error.message.contains("dateOfBirth"))
            #expect(!error.message.contains("DecodingError"))
            // Still identifiable as a decoding failure by its details, which is
            // how a caller tells it apart without reading the message.
            #expect(error.details == "decoding")
        }
    }

    @Test("A 401 is still classified as an auth error")
    func unauthorizedIsAnAuthError() async {
        let endpoint = StubUserEndpoint(currentUser: {
            .unauthorized(.init(body: .any(HTTPBody(""))))
        })
        do {
            _ = try await UserService(client: endpoint).currentUser()
            Issue.record("expected a failure")
        } catch let error as APIError {
            #expect(error.isAuthError)
        } catch {
            Issue.record("expected an APIError")
        }
    }

}
