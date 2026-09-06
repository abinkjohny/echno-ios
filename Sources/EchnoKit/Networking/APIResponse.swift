import Foundation

/// Generic wrapper around a successful backend response.
///
/// Not every endpoint wraps its payload — many return the DTO directly, and
/// the generated client models each response exactly as the document declares
/// it. This type is for the places that do send the envelope.
public struct APIResponse<T: Decodable & Sendable>: Decodable, Sendable {

    /// The payload returned by the backend.
    public let data: T

    /// Optional human-readable message from the backend.
    public let message: String?

    /// Operation success flag. Defaults to `true` when the backend omits it.
    public let success: Bool

    public init(data: T, message: String? = nil, success: Bool = true) {
        self.data = data
        self.message = message
        self.success = success
    }

    private enum CodingKeys: String, CodingKey {
        case data, message, success
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode(T.self, forKey: .data)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
    }
}

/// An acknowledgement-only response — the third of the three mutation response
/// shapes the backend uses (see the mutation-response discipline in
/// `local-docs/ios-action-plan.md` §6).
///
/// Services whose endpoint returns this should be typed `async throws -> Void`
/// and their store should refetch the affected keys rather than trying to patch
/// the cache from the response.
public struct APIAcknowledgement: Decodable, Sendable {
    public let message: String?
    public let success: Bool

    private enum CodingKeys: String, CodingKey { case message, success }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
    }
}
