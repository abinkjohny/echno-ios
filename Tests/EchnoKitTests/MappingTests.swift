import Foundation
import Testing
@testable import EchnoKit

@Suite("Mapping errors")
struct MappingErrorTests {

    @Test("A missing field names both the DTO and the field")
    func namesDTOAndField() {
        // The whole point of the mapping layer. "unexpectedly found nil" tells
        // you nothing at 2am; "UserDto.id was null" tells you which contract
        // broke and where to look.
        let error = MappingError.missing(field: "id", in: "UserDto")
        #expect(error.dto == "UserDto")
        #expect(error.field == "id")
        #expect(error.errorDescription?.contains("UserDto") == true)
        #expect(error.errorDescription?.contains("id") == true)
    }

    @Test("An unrecognised enum value is reported with the value itself")
    func reportsUnrecognisedValue() {
        // A role the app has never heard of means the backend added one. The
        // value has to survive into the message or the fix is guesswork.
        let error = MappingError.unrecognised("ARCHITECT", field: "role", in: "UserDto")
        #expect(error.errorDescription?.contains("ARCHITECT") == true)
        #expect(error.field == "role")
    }

    @Test("Errors compare equal by DTO, field and reason")
    func equatable() {
        #expect(MappingError.missing(field: "id", in: "UserDto")
                == MappingError.missing(field: "id", in: "UserDto"))
        #expect(MappingError.missing(field: "id", in: "UserDto")
                != MappingError.missing(field: "email", in: "UserDto"))
    }
}

@Suite("Requiring invariants")
struct RequireTests {

    @Test("A present value passes through unwrapped")
    func unwrapsPresentValue() throws {
        let id: Int64? = 42
        #expect(try require(id, "id", in: "UserDto") == 42)
    }

    @Test("A nil value throws, naming what was missing")
    func throwsOnNil() {
        let name: String? = nil
        #expect(throws: MappingError.missing(field: "name", in: "UserDto")) {
            try require(name, "name", in: "UserDto")
        }
    }

    @Test("An empty string counts as present, not missing")
    func emptyStringIsPresent() throws {
        // The backend distinguishes "" from null and so must this. Treating ""
        // as missing would reject rows the backend considers perfectly valid.
        #expect(try require("" as String?, "address", in: "UserDto") == "")
    }
}
