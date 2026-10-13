import Foundation
import EchnoAPI

/// An organization the signed-in user belongs to.
///
/// `X-Organization-Id` is a tenant boundary, so this type is what the app has
/// instead of a guess: the switcher offers only these, and the header carries
/// only an id that came from one. Nothing here is inferred from user input —
/// see `CLAUDE.md` § Security.
///
/// Follows the shape ``User`` establishes: `struct`, `let`-only, `Sendable`,
/// `Hashable`, `Identifiable`, with invariants separated from honest optionals
/// once, at the mapping boundary.
public struct Organization: Sendable, Hashable, Identifiable {

    /// Invariant. The id *is* the tenant boundary — a row without one cannot be
    /// selected, and a switcher entry that cannot be selected is a trap.
    public let id: Int64

    /// Invariant. The switcher has nothing to render without it, and an entry
    /// labelled with a blank is worse than an absent one.
    public let name: String

    // Genuinely optional. An organization part-way through setup is an ordinary
    // row, not a broken one.
    public let email: String?
    public let phone: String?
    public let address: String?
    public let website: URL?
    public let logoURL: URL?
    public let createdAt: Date?

    /// Whether the organization is open for business.
    ///
    /// Not optional, though the DTO's field is: see the mapping for why absence
    /// is read as active.
    public let isActive: Bool

    public init(
        id: Int64,
        name: String,
        email: String? = nil,
        phone: String? = nil,
        address: String? = nil,
        website: URL? = nil,
        logoURL: URL? = nil,
        createdAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
        self.website = website
        self.logoURL = logoURL
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

extension Organization {

    /// One or two letters for the switcher's avatar, derived the same way a
    /// person's are — see ``initials(of:)``.
    public var initials: String { EchnoKit.initials(of: name) }

    /// The DTO's name, used in mapping errors so a failure says which contract
    /// broke.
    static let dtoName = "OrganizationDto"

    /// Maps the generated DTO into the domain.
    ///
    /// Deliberately **internal**, like ``User``'s: a public initializer would
    /// put `Components.Schemas.OrganizationDto` in `EchnoKit`'s public API and
    /// make every regeneration a breaking change for consumers.
    ///
    /// `employees` and `projects` are on the DTO and are not mapped. They are
    /// collections of further DTOs that nothing on this screen reads, and
    /// pulling them into the domain would make an organization expensive to
    /// hold and couple this type to two modules that have not been ported.
    ///
    /// - Throws: ``MappingError`` naming the field when an invariant is null.
    init(_ dto: Components.Schemas.OrganizationDto) throws {
        self.init(
            id: try require(dto.id, "id", in: Self.dtoName),
            name: try require(dto.organizationName, "organizationName", in: Self.dtoName),
            email: dto.organizationEmail,
            phone: dto.organizationPhone,
            address: dto.organizationAddress,
            // A field that will not parse as a URL is dropped rather than
            // thrown on. A malformed website is not a reason to withhold the
            // organization someone needs to select.
            website: dto.organizationWebsite.flatMap(URL.init(string:)),
            logoURL: dto.organizationLogo.flatMap(URL.init(string:)),
            createdAt: dto.createdAt,
            // Absent is read as active. The alternative hides an organization
            // from its own members because a column was never populated —
            // absence is not a statement that it is closed, and the member is
            // the one left with an empty switcher and no way to tell why.
            isActive: dto.isActive ?? true
        )
    }
}

extension Organization {

    /// Which organization the app should act in, given what the user belongs to
    /// and what their profile says they prefer.
    ///
    /// Returns `nil` when it cannot be decided, and that is the important case.
    /// `X-Organization-Id` is a tenant boundary: choosing one on the user's
    /// behalf means they may file an attendance record or an indent against the
    /// wrong site without ever having been asked. So ambiguity is reported, not
    /// resolved, and the UI asks.
    ///
    /// - Parameters:
    ///   - organizations: Everything the user is a member of.
    ///   - preferred: `User.defaultOrganizationID`, which may be stale — it
    ///     survives being removed from an organization, and honouring it then
    ///     would send a header for a tenant the caller has no membership in.
    ///     Only honoured when it matches a current membership.
    public static func selection(
        from organizations: [Organization],
        preferring preferred: Int64?
    ) -> Organization? {
        if let preferred, let match = organizations.first(where: { $0.id == preferred }) {
            return match
        }
        // Nobody should be made to pick from a list of one.
        return organizations.count == 1 ? organizations.first : nil
    }
}
