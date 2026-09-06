import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import EchnoKit
import EchnoAPI

/// Records the request it is handed and answers with a canned response, so a
/// middleware can be tested without a backend.
private actor RecordingTransport: ClientTransport {
    private(set) var lastRequest: HTTPRequest?
    private let status: Int
    private let body: String

    init(status: Int = 201, body: String = "{}") {
        self.status = status
        self.body = body
    }

    func send(
        _ request: HTTPRequest,
        body requestBody: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        lastRequest = request
        return (
            HTTPResponse(
                status: .init(code: status),
                headerFields: [.contentType: "application/json"]
            ),
            HTTPBody(body)
        )
    }

    func recorded() -> HTTPRequest? { lastRequest }
}

private struct StubCredentials: APICredentialProvider {
    var token = "test-token"
    var organizationID: Int64? = 42

    func accessToken() async throws -> String { token }
    func currentOrganizationID() async -> Int64? { organizationID }
}

private struct FailingCredentials: APICredentialProvider {
    func accessToken() async throws -> String {
        throw APIError(message: "Session expired", status: 401)
    }
    func currentOrganizationID() async -> Int64? { nil }
}

@Suite("Authentication middleware")
struct AuthenticationMiddlewareTests {

    private func send(
        operationID: String,
        credentials: any APICredentialProvider = StubCredentials()
    ) async throws -> HTTPRequest? {
        let transport = RecordingTransport()
        let middleware = AuthenticationMiddleware(credentials: credentials)
        _ = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/thing"),
            body: nil,
            baseURL: URL(string: "https://backend.echno.in/api/v1")!,
            operationID: operationID
        ) { request, body, url in
            try await transport.send(request, body: body, baseURL: url, operationID: operationID)
        }
        return await transport.recorded()
    }

    @Test("An authenticated operation carries the bearer token and the tenant")
    func attachesCredentials() async throws {
        let request = try #require(await send(operationID: "getEmployeeById"))
        #expect(request.headerFields[.authorization] == "Bearer test-token")
        #expect(request.headerFields[.xOrganizationID] == "42")
    }

    @Test("Registration is exempt — it is permitAll on the backend")
    func skipsUnauthenticatedOperations() async throws {
        // Credentials that would throw if consulted, proving the exemption is
        // checked before the token is requested rather than after.
        let request = try #require(
            await send(operationID: "registerUser", credentials: FailingCredentials())
        )
        #expect(request.headerFields[.authorization] == nil)
        #expect(request.headerFields[.xOrganizationID] == nil)
    }

    @Test("No tenant header when no organization is selected yet")
    func omitsTenantDuringBootstrap() async throws {
        let credentials = StubCredentials(organizationID: nil)
        let request = try #require(await send(operationID: "getCurrentUser", credentials: credentials))
        #expect(request.headerFields[.authorization] == "Bearer test-token")
        #expect(request.headerFields[.xOrganizationID] == nil)
    }

    @Test("A failed refresh surfaces as an auth error, not a silent 401 later")
    func propagatesCredentialFailure() async {
        await #expect(throws: APIError.self) {
            _ = try await send(operationID: "getEmployeeById", credentials: FailingCredentials())
        }
    }
}

@Suite("Generated client wiring")
struct GeneratedClientTests {

    @Test("The register operation exists and is reachable through the client")
    func registerOperationIsGenerated() async throws {
        let transport = RecordingTransport(
            status: 201,
            body: #"{"success":true,"message":"created"}"#
        )
        let client = EchnoClient.make(
            credentials: StubCredentials(),
            transport: transport
        )

        _ = try? await client.registerUser(
            .init(
                body: .json(
                    // Parameter order is the generator's: alphabetical, with the
                    // schema's `required` fields non-optional and the rest not.
                    // UserRegistrationDto is one of the 110 schemas that does
                    // declare `required`, which is why these are not all `T?`.
                    .init(
                        acceptTerms: true,
                        dateOfBirth: Date(timeIntervalSince1970: 0),
                        email: "john@company.com",
                        gender: "Male",
                        name: "John Doe",
                        password: "Str0ng!pass",
                        phone: "+911234567890",
                        role: "EMPLOYEE",
                        userName: "john_doe"
                    )
                )
            )
        )

        let request = try #require(await transport.recorded())
        #expect(request.method == .post)
        #expect(request.path?.hasSuffix("/auth/register") == true)
        // The exemption must hold end to end, not only in the middleware test.
        #expect(request.headerFields[.authorization] == nil)
    }
}

@Suite("Server environment")
struct ServerEnvironmentTests {

    @Test("Production points at the live backend's versioned API root")
    func production() {
        #expect(ServerEnvironment.production.baseURL.absoluteString
                == "https://backend.echno.in/api/v1")
    }

    @Test("A custom environment is used verbatim")
    func custom() {
        let local = URL(string: "http://10.0.0.5:8080/api/v1")!
        #expect(ServerEnvironment.custom(local).baseURL == local)
    }
}

@Suite("Error mapping")
struct ErrorMappingTests {

    @Test("A ClientError is unwrapped to the cause the app can act on")
    func unwrapsClientError() {
        // The generated client wraps everything it throws. Left wrapped, a
        // timeout would present as a generic failure and the UI would offer the
        // wrong recovery.
        let wrapped = ClientError(
            operationID: "getEmployeeById",
            operationInput: "input",
            causeDescription: "timed out",
            underlyingError: URLError(.timedOut)
        )
        #expect(APIError.from(wrapped).isTimeout)
    }

    @Test("An APIError wrapped by the client still passes through intact")
    func unwrapsToAPIError() {
        let original = APIError(message: "Session expired", status: 401)
        let wrapped = ClientError(
            operationID: "getEmployeeById",
            operationInput: "input",
            causeDescription: "auth",
            underlyingError: original
        )
        #expect(APIError.from(wrapped) == original)
    }

    @Test("An unrecognised error still produces a usable APIError")
    func unknownError() {
        struct Odd: Error {}
        let mapped = APIError.from(Odd())
        #expect(mapped.status == 0)
        #expect(!mapped.message.isEmpty)
    }

    @Test("A timeout stays distinguishable from a plain network failure")
    func timeout() {
        let mapped = APIError.from(URLError(.timedOut))
        #expect(mapped.isTimeout)
        #expect(!mapped.isNetworkFailure)
    }

    @Test("Offline maps to a network failure")
    func offline() {
        let mapped = APIError.from(URLError(.notConnectedToInternet))
        #expect(mapped.isNetworkFailure)
        #expect(!mapped.isTimeout)
    }

    @Test("An APIError passes through unchanged")
    func passthrough() {
        let original = APIError(message: "Nope", status: 403)
        let mapped = APIError.from(original)
        #expect(mapped == original)
        #expect(mapped.isAuthError)
    }
}
