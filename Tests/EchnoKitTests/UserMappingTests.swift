import Foundation
import Testing
@testable import EchnoKit
import EchnoAPI

@Suite("User mapping")
struct UserMappingTests {

    @Test("A complete DTO maps to a domain user with no optionals to unwrap")
    func mapsCompleteDTO() throws {
        var raw = Components.Schemas.UserDto()
        raw.id = 42
        raw.name = "Ravi Kumar"
        raw.email = "ravi@echno.in"
        raw.phone = "+911234567890"
        raw.role = .EMPLOYEE
        raw.dateOfBirth = Date(timeIntervalSince1970: 0)
        raw.defaultOrganizationId = 7

        let user = try User(raw)
        #expect(user.id == 42)
        #expect(user.name == "Ravi Kumar")
        #expect(user.email == "ravi@echno.in")
        #expect(user.role == .employee)
        #expect(user.defaultOrganizationID == 7)
    }

    @Test("A null id is refused, naming the DTO and field")
    func refusesNullID() {
        var raw = Components.Schemas.UserDto()
        raw.name = "Ravi Kumar"
        raw.email = "ravi@echno.in"
        #expect(throws: MappingError.missing(field: "id", in: "UserDto")) {
            try User(raw)
        }
    }

    @Test("A null name is refused", arguments: ["name", "email"])
    func refusesNullInvariants(field: String) {
        var raw = Components.Schemas.UserDto()
        raw.id = 42
        raw.name = field == "name" ? nil : "Ravi Kumar"
        raw.email = field == "email" ? nil : "ravi@echno.in"
        #expect(throws: MappingError.missing(field: field, in: "UserDto")) {
            try User(raw)
        }
    }

    @Test("Genuinely optional fields stay optional rather than being invented")
    func keepsRealOptionalsOptional() throws {
        // A user with no default organization is an ordinary state, not a
        // broken row — they have not joined one yet. Requiring it would reject
        // every newly registered account.
        var raw = Components.Schemas.UserDto()
        raw.id = 42
        raw.name = "Ravi Kumar"
        raw.email = "ravi@echno.in"

        let user = try User(raw)
        #expect(user.defaultOrganizationID == nil)
        #expect(user.phone == nil)
        #expect(user.dateOfBirth == nil)
        #expect(user.role == nil)
    }

    @Test("The generated role enum is re-exported as the domain role")
    func reExportsRole() throws {
        // The view layer must never see Components.Schemas.UserDto.rolePayload.
        // UserRole already exists for the registration form; mapping onto it
        // keeps one role type in the app rather than two that drift.
        for generated in Components.Schemas.UserDto.rolePayload.allCases {
            var raw = Components.Schemas.UserDto()
            raw.id = 1; raw.name = "n"; raw.email = "e"
            raw.role = generated
            let mapped = try #require(try User(raw).role)
            #expect(mapped.rawValue == generated.rawValue)
        }
    }

    @Test("Every backend role has a domain case, so none can silently vanish")
    func roleCoverageIsComplete() {
        // If the backend adds a role, this fails here rather than surfacing as
        // a user whose role quietly reads as nil.
        let generated = Set(Components.Schemas.UserDto.rolePayload.allCases.map(\.rawValue))
        let domain = Set(UserRole.allCases.map(\.rawValue))
        #expect(generated == domain)
    }

    @Test("Identity is the id, so SwiftUI diffing survives a field change")
    func identity() throws {
        var raw = Components.Schemas.UserDto()
        raw.id = 42; raw.name = "Ravi Kumar"; raw.email = "ravi@echno.in"
        var renamed = raw
        renamed.name = "Ravi K."

        #expect(try User(raw).id == User(renamed).id)
        #expect(try User(raw) != User(renamed))
    }
}

@Suite("User endpoint selection")
struct UserEndpointTests {

    // The generated operation names do not say which controller family they
    // belong to, and the _1 suffix follows document order rather than the /web
    // split. These assertions are read off openapi.json; if a regeneration
    // reorders the document and swaps the suffixes, this fails instead of the
    // app silently calling the wrong controller.
    @Test("The operations the user service calls are the /web ones", arguments: [
        ("getCurrentUser", "/api/v1/user/web"),
        ("partialUpdateAUser_1", "/api/v1/user/web/{id}"),
        ("readAllOrganizationsForCurrentUser_1", "/api/v1/user/web/{userId}/organizations")
    ])
    func operationsTargetWebControllers(operationID: String, path: String) throws {
        let document = try OpenAPIDocumentFixture.load()
        #expect(document.path(forOperation: operationID) == path)
    }

    @Test("The current-user call is the tenant-exempt one")
    func currentUserIsTenantExempt() throws {
        // TenantFilter.preTenantReason exempts /api/v1/user/web only. The
        // mobile twin /api/v1/user is tenant-scoped, so it answers 400 for a
        // user in more than one organization — which is every bootstrap.
        let document = try OpenAPIDocumentFixture.load()
        #expect(document.path(forOperation: "getCurrentUser") == "/api/v1/user/web")
        #expect(document.path(forOperation: "readAnUser") == "/api/v1/user")
    }
}

@Suite("User initials")
struct UserInitialsTests {

    private func user(_ name: String) -> User {
        User(id: 1, name: name, email: "a@b.c")
    }

    @Test("Two words give two initials")
    func twoWords() {
        #expect(user("Ravi Kumar").initials == "RK")
    }

    @Test("One word gives one initial")
    func oneWord() {
        #expect(user("Ravi").initials == "R")
    }

    @Test("More than two words uses the first and last")
    func manyWords() {
        // Middle names are common here; "RKS" reads as a different person than
        // "RS", and the surname is the part people recognise.
        #expect(user("Ravi Kumar Sharma").initials == "RS")
    }

    @Test("Extra whitespace does not become an initial")
    func messyWhitespace() {
        #expect(user("  Ravi   Kumar  ").initials == "RK")
    }

    @Test("A name that is only whitespace falls back rather than showing nothing")
    func blankName() {
        // An empty avatar reads as a rendering bug. A person glyph reads as
        // "no name on file", which is the truth.
        #expect(user("   ").initials == "")
    }

    @Test("Initials are uppercased regardless of how the name was entered")
    func casing() {
        #expect(user("ravi kumar").initials == "RK")
    }

    @Test("Non-Latin names take whole grapheme clusters")
    func nonLatin() throws {
        // Derived, not hand-written: in Malayalam a consonant plus its vowel
        // sign is one Character, so the initial of കുമാർ is കു and not ക —
        // splitting it would drop the vowel and spell something else.
        let given = "രവി", family = "കുമാർ"
        let expected = String(try #require(given.first)) + String(try #require(family.first))
        #expect(user("\(given) \(family)").initials == expected)
        #expect(expected.count == 2, "two Characters, whatever their scalar count")
    }
}
