import Foundation
import Testing
@testable import EchnoCore

/// A draft that passes every rule, so each test can vary one field and be sure
/// the failure it asserts is the one it caused.
private func validDraft(
    userName: String = "john_doe",
    name: String = "John Doe",
    email: String = "john@company.com",
    password: String = "Str0ng!pass",
    confirmPassword: String = "Str0ng!pass",
    phone: String = "+911234567890",
    gender: Gender = .male,
    dateOfBirth: Date? = Date(timeIntervalSince1970: 0),
    role: UserRole? = .employee,
    acceptTerms: Bool = true
) -> RegistrationDraft {
    RegistrationDraft(
        userName: userName,
        name: name,
        email: email,
        password: password,
        confirmPassword: confirmPassword,
        phone: phone,
        gender: gender,
        dateOfBirth: dateOfBirth,
        role: role,
        acceptTerms: acceptTerms
    )
}

@Suite("Registration validation")
struct RegistrationValidationTests {

    @Test("A complete, well-formed draft has no errors")
    func validDraftPasses() {
        #expect(validDraft().validate().isEmpty)
    }

    // MARK: Username

    @Test("Username is required")
    func usernameRequired() {
        #expect(validDraft(userName: "").validate()[.userName] != nil)
    }

    @Test(
        "Username must be 4 to 20 characters",
        arguments: ["abc", String(repeating: "a", count: 21)]
    )
    func usernameLength(candidate: String) {
        #expect(validDraft(userName: candidate).validate()[.userName] != nil)
    }

    @Test("Username boundaries are inclusive", arguments: ["abcd", String(repeating: "a", count: 20)])
    func usernameBoundaries(candidate: String) {
        #expect(validDraft(userName: candidate).validate()[.userName] == nil)
    }

    @Test(
        "Username rejects characters outside letters, digits, dot, underscore and hyphen",
        arguments: ["john doe", "john@doe", "john+doe", "jöhn_doe"]
    )
    func usernameCharacters(candidate: String) {
        #expect(validDraft(userName: candidate).validate()[.userName] != nil)
    }

    // MARK: Name

    @Test("Full name is required and must be at least two characters")
    func nameLength() {
        #expect(validDraft(name: "").validate()[.name] != nil)
        #expect(validDraft(name: "J").validate()[.name] != nil)
        #expect(validDraft(name: "Jo").validate()[.name] == nil)
    }

    @Test("Name accepts spaces, apostrophes, dots and hyphens", arguments: [
        "Mary-Jane O'Neill", "J. R. Smith", "Anand Rajashekar"
    ])
    func nameAcceptsRealNames(candidate: String) {
        #expect(validDraft(name: candidate).validate()[.name] == nil)
    }

    @Test("Name rejects digits and symbols", arguments: ["John3", "John_Doe", "John@"])
    func nameRejectsSymbols(candidate: String) {
        #expect(validDraft(name: candidate).validate()[.name] != nil)
    }

    // MARK: Email

    @Test("Email must look like an address", arguments: [
        "", "john", "john@", "@company.com", "john@company", "john doe@company.com"
    ])
    func emailRejected(candidate: String) {
        #expect(validDraft(email: candidate).validate()[.email] != nil)
    }

    @Test("Ordinary addresses are accepted", arguments: [
        "john@company.com", "john.doe+tag@sub.company.co.in"
    ])
    func emailAccepted(candidate: String) {
        #expect(validDraft(email: candidate).validate()[.email] == nil)
    }

    // MARK: Password

    @Test("Each password rule is reported, in the order the web client reports them")
    func passwordRulesInOrder() {
        #expect(RegistrationDraft.passwordProblem("") != nil)
        #expect(RegistrationDraft.passwordProblem("Ab1!") == "Password must be at least 8 characters long")
        #expect(RegistrationDraft.passwordProblem("lowercase1!") == "Password must contain at least one uppercase letter")
        #expect(RegistrationDraft.passwordProblem("UPPERCASE1!") == "Password must contain at least one lowercase letter")
        #expect(RegistrationDraft.passwordProblem("NoDigits!!") == "Password must contain at least one number")
        #expect(RegistrationDraft.passwordProblem("NoSpecial1") == "Password must contain at least one special character")
        #expect(RegistrationDraft.passwordProblem("Str0ng!pass") == nil)
    }

    @Test("Confirmation must match")
    func confirmationMustMatch() {
        #expect(validDraft(confirmPassword: "").validate()[.confirmPassword] != nil)
        #expect(validDraft(confirmPassword: "Different1!").validate()[.confirmPassword] != nil)
    }

    @Test("Strength counts satisfied rules, from none to all five")
    func strength() {
        #expect(validDraft(password: "").passwordStrength == 0)
        #expect(validDraft(password: "abcdefgh").passwordStrength == 2)   // length + lowercase
        #expect(validDraft(password: "Str0ng!pass").passwordStrength == 5)
    }

    // MARK: Phone

    @Test("Phone accepts an optional plus and 8 to 15 digits", arguments: [
        "+911234567890", "911234567890", "12345678"
    ])
    func phoneAccepted(candidate: String) {
        #expect(validDraft(phone: candidate).validate()[.phone] == nil)
    }

    @Test("Phone rejects letters, separators and a leading zero", arguments: [
        "", "0123456789", "+91 12345 67890", "+91-1234567890", "phone"
    ])
    func phoneRejected(candidate: String) {
        #expect(validDraft(phone: candidate).validate()[.phone] != nil)
    }

    // MARK: Remaining required fields

    @Test("Date of birth, role and the terms are all required")
    func remainingRequiredFields() {
        #expect(validDraft(dateOfBirth: nil).validate()[.dateOfBirth] != nil)
        #expect(validDraft(role: nil).validate()[.role] != nil)
        #expect(validDraft(acceptTerms: false).validate()[.acceptTerms] != nil)
    }

    @Test("An empty draft reports every field at once, not just the first")
    func reportsAllFailuresTogether() {
        let errors = RegistrationDraft().validate()
        let expected: Set<RegistrationField> = [
            .userName, .name, .email, .password, .confirmPassword,
            .phone, .dateOfBirth, .role, .acceptTerms
        ]
        #expect(Set(errors.keys) == expected)
    }
}

@Suite("Registration domain enums")
struct RegistrationEnumTests {

    @Test("Role wire values match the backend UserRole enum")
    func roleWireValues() {
        // Source: echno-backend user/enums/UserRole.java
        #expect(Set(UserRole.allCases.map(\.rawValue)) == [
            "OWNER", "CO_FOUNDER", "HR_MANAGER", "EMPLOYEE",
            "STUDENT", "MANAGEMENT", "ADMINISTRATOR"
        ])
    }

    @Test("Every role has a display label distinct from its wire value")
    func roleLabels() {
        for role in UserRole.allCases {
            #expect(!role.label.isEmpty)
            #expect(role.label != role.rawValue)
        }
    }

    @Test("Gender wire values match what the backend expects")
    func genderWireValues() {
        #expect(Set(Gender.allCases.map(\.rawValue)) == ["Male", "Female", "Other"])
    }
}

@Suite("Minimum age")
struct MinimumAgeTests {

    @Test("The newest allowed birth date is exactly 18 years ago")
    func newestAllowed() throws {
        let now = Date(timeIntervalSince1970: 1_788_704_585)   // 2026-09-06T14:23:05Z
        let range = RegistrationDraft.dateOfBirthRange(now: now)
        let eighteenYearsAgo = try #require(
            Calendar(identifier: .gregorian).date(byAdding: .year, value: -18, to: now)
        )
        #expect(range.upperBound == eighteenYearsAgo)
    }

    @Test("Someone turning 18 tomorrow is outside the range")
    func justUnderEighteen() throws {
        let now = Date(timeIntervalSince1970: 1_788_704_585)
        let range = RegistrationDraft.dateOfBirthRange(now: now)
        let calendar = Calendar(identifier: .gregorian)
        let tomorrowsEighteenth = try #require(
            calendar.date(byAdding: .day, value: 1, to: range.upperBound)
        )
        #expect(!range.contains(tomorrowsEighteenth))
    }
}
