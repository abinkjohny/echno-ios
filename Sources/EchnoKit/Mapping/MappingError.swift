import Foundation

/// A generated DTO did not satisfy an invariant the domain depends on.
///
/// ## Why this type exists
///
/// 185 of the backend's schemas omit `required`, so `swift-openapi-generator`
/// is obliged to make every property optional — including `UserDto.id`, which
/// is never null on any row. Carrying that optionality into the app would mean
/// `user.id?` at every call site and a crash or a blank screen the first time
/// one of them was force-unwrapped.
///
/// Instead the invariant is asserted once, here at the mapping boundary. When
/// the backend does return null for something the app treats as guaranteed,
/// this says which DTO and which field — the difference between a bug report
/// that can be acted on and "Unexpectedly found nil".
public struct MappingError: Error, Sendable, Equatable {

    /// Why the mapping failed.
    public enum Reason: Sendable, Equatable {
        /// A field the domain requires was absent or null.
        case missing
        /// A value outside the set the domain models — almost always the
        /// backend having added an enum case the app predates.
        case unrecognised(String)
    }

    /// The generated DTO being mapped, e.g. `"UserDto"`.
    public let dto: String

    /// The offending property, e.g. `"id"`.
    public let field: String

    public let reason: Reason

    public init(dto: String, field: String, reason: Reason) {
        self.dto = dto
        self.field = field
        self.reason = reason
    }

    /// A field the domain requires was null.
    public static func missing(field: String, in dto: String) -> MappingError {
        MappingError(dto: dto, field: field, reason: .missing)
    }

    /// A value the domain does not model.
    public static func unrecognised(
        _ value: String,
        field: String,
        in dto: String
    ) -> MappingError {
        MappingError(dto: dto, field: field, reason: .unrecognised(value))
    }
}

extension MappingError: LocalizedError {
    public var errorDescription: String? {
        switch reason {
        case .missing:
            "\(dto).\(field) was null, but the app requires it."
        case .unrecognised(let value):
            "\(dto).\(field) had the unrecognised value \"\(value)\"."
        }
    }
}

/// Unwraps a generated optional the domain treats as guaranteed.
///
/// Reads at the call site as a statement of the invariant:
///
/// ```swift
/// id: try require(dto.id, "id", in: Self.dtoName)
/// ```
///
/// - Parameters:
///   - value: The generated property.
///   - field: Its name, for the error.
///   - dto: The DTO's name, for the error.
/// - Returns: The unwrapped value.
/// - Throws: ``MappingError`` naming the DTO and field when `value` is `nil`.
public func require<T>(
    _ value: T?,
    _ field: String,
    in dto: String
) throws -> T {
    guard let value else {
        throw MappingError.missing(field: field, in: dto)
    }
    return value
}
