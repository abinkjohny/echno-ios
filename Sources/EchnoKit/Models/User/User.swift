import Foundation
import EchnoAPI

/// A user of the platform.
///
/// ## The convention this file establishes
///
/// Every domain model in `EchnoKit` follows this shape, and every module port
/// copies it:
///
/// - **`struct`, `let`-only, `Sendable`, `Hashable`, `Identifiable`.** Mutation
///   produces a new value; there is no shared mutable model to race on.
/// - **Non-optional where the field is invariant**, optional only where the
///   backend genuinely returns null for ordinary rows. The generated DTO makes
///   everything optional because the schema omits `required`, so this
///   distinction is made here, deliberately, once — not inferred at call sites.
/// - **No generated type in the public surface.** `Components.Schemas.*` never
///   escapes the mapping. Backend enums are re-exported as domain enums so the
///   app has one vocabulary.
public struct User: Sendable, Hashable, Identifiable {

    // Invariants. Null in any of these means the contract broke, and mapping
    // says so rather than letting the app carry the doubt.
    public let id: Int64
    public let name: String
    public let email: String

    // Genuinely optional. A user who has not joined an organization, filled in
    // a profile, or set a role is an ordinary row, not a broken one.
    public let phone: String?
    public let role: UserRole?
    public let gender: String?
    public let dateOfBirth: Date?
    public let defaultOrganizationID: Int64?
    public let profilePictureURL: URL?
    public let qualification: String?
    public let experience: Int?
    public let skills: [String]
    public let certifications: [String]
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: Int64,
        name: String,
        email: String,
        phone: String? = nil,
        role: UserRole? = nil,
        gender: String? = nil,
        dateOfBirth: Date? = nil,
        defaultOrganizationID: Int64? = nil,
        profilePictureURL: URL? = nil,
        qualification: String? = nil,
        experience: Int? = nil,
        skills: [String] = [],
        certifications: [String] = [],
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.role = role
        self.gender = gender
        self.dateOfBirth = dateOfBirth
        self.defaultOrganizationID = defaultOrganizationID
        self.profilePictureURL = profilePictureURL
        self.qualification = qualification
        self.experience = experience
        self.skills = skills
        self.certifications = certifications
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension User {

    /// The DTO's name, used in mapping errors so a failure says which contract
    /// broke.
    static let dtoName = "UserDto"

    /// Maps the generated DTO into the domain.
    ///
    /// The three `require` calls are the entire point of this layer: they turn
    /// "every field might be nil" into three named invariants and a set of
    /// honest optionals.
    ///
    /// - Throws: ``MappingError`` naming the field when an invariant is null.
    public init(_ dto: Components.Schemas.UserDto) throws {
        self.init(
            id: try require(dto.id, "id", in: Self.dtoName),
            name: try require(dto.name, "name", in: Self.dtoName),
            email: try require(dto.email, "email", in: Self.dtoName),
            phone: dto.phone,
            // An unknown role maps to nil rather than throwing. The generator
            // already constrains this to the document's enum, so a value
            // outside it cannot arrive; a role the app cannot show is also not
            // worth refusing an entire profile over.
            role: dto.role.flatMap { UserRole(rawValue: $0.rawValue) },
            gender: dto.gender,
            dateOfBirth: dto.dateOfBirth,
            defaultOrganizationID: dto.defaultOrganizationId,
            profilePictureURL: dto.profilePictureUrl.flatMap(URL.init(string:)),
            qualification: dto.qualification,
            experience: dto.experience.map(Int.init),
            // A null collection and an empty one mean the same thing to a list
            // view. Collapsing here spares every call site an `?? []`.
            skills: dto.skills ?? [],
            certifications: dto.certifications ?? [],
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}
