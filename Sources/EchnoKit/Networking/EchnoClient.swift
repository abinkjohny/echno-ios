import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import EchnoAPI

/// Which backend the app talks to.
public enum ServerEnvironment: Sendable {
    case production
    case custom(URL)

    public var baseURL: URL {
        switch self {
        case .production:
            URL(string: "https://backend.echno.in/api/v1")!
        case .custom(let url):
            url
        }
    }
}

/// Builds the generated client with Echno's middleware attached.
///
/// Services take a narrow protocol from `Endpoints+Narrow.swift` rather than
/// this type, so a test double implements one or two operations instead of the
/// whole document.
public enum EchnoClient {

    /// - Returns: The generated `Client`, which conforms to every narrow
    ///   service protocol in `Endpoints+Narrow.swift`. Returning the concrete
    ///   type rather than `any APIProtocol` is what lets a service ask for just
    ///   the operations it uses.
    public static func make(
        environment: ServerEnvironment = .production,
        credentials: any APICredentialProvider,
        transport: any ClientTransport = URLSessionTransport()
    ) -> Client {
        Client(
            serverURL: environment.baseURL,
            transport: transport,
            middlewares: [AuthenticationMiddleware(credentials: credentials)]
        )
    }
}

extension APIError {

    /// Maps an error thrown by the generated client onto ``APIError``.
    ///
    /// The generated client wraps everything in `ClientError`; what the app
    /// wants is the cause. Timeouts and offline are worth distinguishing
    /// because the UI says something different for each, and a timed-out
    /// mutation may or may not have been applied.
    public static func from(_ error: any Error) -> APIError {
        if let apiError = error as? APIError { return apiError }

        let underlying = (error as? ClientError)?.underlyingError ?? error
        if let apiError = underlying as? APIError { return apiError }

        if let urlError = underlying as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout()
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
                return .network(urlError.localizedDescription)
            default:
                return .network(urlError.localizedDescription)
            }
        }

        return APIError(message: underlying.localizedDescription, status: 0)
    }
}
