import Foundation
import Testing
@testable import EchnoKit
import EchnoAPI

@Suite("Organization mapping")
struct OrganizationMappingTests {

    @Test("A complete DTO maps to a domain organization")
    func mapsCompleteDTO() throws {
        var raw = Components.Schemas.OrganizationDto()
        raw.id = 7
        raw.organizationName = "Tornotron Constructions"
        raw.organizationEmail = "site@tornotron.in"
        raw.organizationPhone = "+914842345678"
        raw.organizationAddress = "Kakkanad, Kochi"
        raw.organizationWebsite = "https://tornotron.in"
        raw.organizationLogo = "https://cdn.echno.in/logos/7.png"
        raw.isActive = true

        let org = try Organization(raw)
        #expect(org.id == 7)
        #expect(org.name == "Tornotron Constructions")
        #expect(org.email == "site@tornotron.in")
        #expect(org.address == "Kakkanad, Kochi")
        #expect(org.isActive)
        #expect(org.logoURL?.host() == "cdn.echno.in")
    }

    @Test("A null id is refused, naming the DTO and field")
    func refusesNullID() {
        var raw = Components.Schemas.OrganizationDto()
        raw.organizationName = "Tornotron Constructions"
        #expect(throws: MappingError.missing(field: "id", in: "OrganizationDto")) {
            try Organization(raw)
        }
    }

    @Test("A null name is refused")
    func refusesNullName() {
        var raw = Components.Schemas.OrganizationDto()
        raw.id = 7
        #expect(throws: MappingError.missing(field: "organizationName", in: "OrganizationDto")) {
            try Organization(raw)
        }
    }

    @Test("Everything but id and name is allowed to be absent")
    func toleratesASparseRow() throws {
        // An organization mid-setup has a name and nothing else. Refusing it
        // would empty the switcher for someone who has only just been invited.
        var raw = Components.Schemas.OrganizationDto()
        raw.id = 7
        raw.organizationName = "Tornotron Constructions"

        let org = try Organization(raw)
        #expect(org.email == nil)
        #expect(org.logoURL == nil)
        #expect(org.address == nil)
    }

    @Test("A missing isActive is treated as active")
    func absentIsActiveMeansActive() throws {
        // The alternative hides an organization from its own members because a
        // column was never populated. Absence is not a statement that it is
        // closed, and the member is the one who would be left with an empty
        // switcher and no way to tell why.
        var raw = Components.Schemas.OrganizationDto()
        raw.id = 7
        raw.organizationName = "Tornotron Constructions"
        #expect(try Organization(raw).isActive)
    }

    @Test("A logo that is not a URL is dropped, not fatal")
    func unusableLogoIsDropped() throws {
        var raw = Components.Schemas.OrganizationDto()
        raw.id = 7
        raw.organizationName = "Tornotron Constructions"
        raw.organizationLogo = ""
        #expect(try Organization(raw).logoURL == nil)
    }

    @Test("Initials come from the organization's own name")
    func initials() throws {
        var raw = Components.Schemas.OrganizationDto()
        raw.id = 7
        raw.organizationName = "Tornotron Constructions"
        // Derived the same way a person's are, so the switcher and the profile
        // row read as one system — see `User.initials`.
        #expect(try Organization(raw).initials == "TC")
    }
}
