import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import EchnoKit
import EchnoAPI

/// Implements only the one operation `OrganizationService` calls.
private final class StubOrganizationEndpoint: OrganizationEndpoint, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _lastUserID: Int64?

    var result: @Sendable () throws -> Operations.readAllOrganizationsForCurrentUser_1.Output

    init(
        result: @escaping @Sendable () throws -> Operations.readAllOrganizationsForCurrentUser_1.Output
            = { .ok(.init(body: .any(HTTPBody(StubOrganizationEndpoint.encoded([
                StubOrganizationEndpoint.organization()
            ]))))) }
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
    static func encoded(_ dtos: [Components.Schemas.OrganizationDto]) -> Data {
        (try? JSONEncoder().encode(dtos)) ?? Data()
    }

    var calls: Int { lock.withLock { _calls } }
    var lastUserID: Int64? { lock.withLock { _lastUserID } }

    func readAllOrganizationsForCurrentUser_1(
        _ input: Operations.readAllOrganizationsForCurrentUser_1.Input
    ) async throws -> Operations.readAllOrganizationsForCurrentUser_1.Output {
        lock.withLock { _calls += 1; _lastUserID = input.path.userId }
        return try result()
    }
}

@Suite("Organization service")
struct OrganizationServiceTests {

    @Test("The user's organizations are fetched and mapped into the domain")
    func fetchesAndMaps() async throws {
        let endpoint = StubOrganizationEndpoint()
        let orgs = try await OrganizationService(client: endpoint).organizations(forUser: 42)
        #expect(orgs.count == 1)
        #expect(orgs.first?.name == "Tornotron Constructions")
        #expect(endpoint.lastUserID == 42)
    }

    @Test("No memberships is an empty list, not a failure")
    func emptyIsNotAnError() async throws {
        let endpoint = StubOrganizationEndpoint(result: {
            .ok(.init(body: .any(HTTPBody(StubOrganizationEndpoint.encoded([])))))
        })
        #expect(try await OrganizationService(client: endpoint).organizations(forUser: 42).isEmpty)
    }

    @Test("A row breaking an invariant fails the call rather than vanishing")
    func badRowIsNotSkipped() async {
        // Dropping it would be kinder to the list and wrong here. This list is
        // the tenant switcher: someone shown one organization when they belong
        // to two will act in the wrong tenant believing they have no choice.
        // Loud is the safe failure mode when the alternative is a silent one.
        let endpoint = StubOrganizationEndpoint(result: {
            .ok(.init(body: .any(HTTPBody(StubOrganizationEndpoint.encoded([
                StubOrganizationEndpoint.organization(),
                StubOrganizationEndpoint.organization(id: 8, name: nil)
            ])))))
        })
        await #expect(throws: (any Error).self) {
            try await OrganizationService(client: endpoint).organizations(forUser: 42)
        }
    }

    @Test(
        "Statuses the document declares keep their code, so a failure can be diagnosed",
        arguments: [403, 404, 400, 409, 422, 500, 502]
    )
    func declaredStatusesKeepTheirCode(status: Int) async {
        let endpoint = StubOrganizationEndpoint(result: {
            switch status {
            case 403: .forbidden(.init(body: .any(HTTPBody(""))))
            case 404: .notFound(.init(body: .any(HTTPBody(""))))
            case 400: .badRequest(.init(body: .any(HTTPBody(""))))
            case 409: .conflict(.init(body: .any(HTTPBody(""))))
            case 422: .unprocessableContent(.init(body: .any(HTTPBody(""))))
            case 500: .internalServerError(.init(body: .any(HTTPBody(""))))
            default: .badGateway(.init(body: .any(HTTPBody(""))))
            }
        })
        do {
            _ = try await OrganizationService(client: endpoint).organizations(forUser: 42)
            Issue.record("expected a failure")
        } catch let error as APIError {
            #expect(error.status == status)
        } catch {
            Issue.record("expected an APIError")
        }
    }

    @Test("A 401 is classified as an auth error even though the document omits it")
    func unauthorizedIsAnAuthError() async {
        // The document declares no 401 for this operation, so the generator
        // emits no case for it and a expired session arrives as `.undocumented`.
        // Left to the catch-all it reads as "unexpected status 401" — the one
        // failure most likely to happen here, described the least usefully.
        let endpoint = StubOrganizationEndpoint(result: {
            .undocumented(statusCode: 401, .init())
        })
        do {
            _ = try await OrganizationService(client: endpoint).organizations(forUser: 42)
            Issue.record("expected a failure")
        } catch let error as APIError {
            #expect(error.isAuthError)
        } catch {
            Issue.record("expected an APIError")
        }
    }

    @Test("A 402 says the subscription lapsed rather than reporting a surprise")
    func paymentRequiredIsNamed() async {
        // The generated case is `code402`, not `paymentRequired`: the generator
        // falls back to the number for a status it has no name for. Searching
        // the Output for the word finds nothing and suggests the case is
        // missing, which is how this was nearly handled in the catch-all.
        let endpoint = StubOrganizationEndpoint(result: {
            .code402(.init(body: .any(HTTPBody(""))))
        })
        do {
            _ = try await OrganizationService(client: endpoint).organizations(forUser: 42)
            Issue.record("expected a failure")
        } catch let error as APIError {
            #expect(error.status == 402)
            #expect(error.message.lowercased().contains("subscription"))
        } catch {
            Issue.record("expected an APIError")
        }
    }
}
