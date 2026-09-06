import Foundation
import Testing
@testable import EchnoKit

@Suite("Registration field order")
struct RegistrationFieldOrderTests {

    @Test("Focus order matches the order the fields are laid out on screen")
    func focusOrder() {
        #expect(RegistrationField.focusOrder == [
            .userName, .name, .email, .password, .confirmPassword, .phone
        ])
    }

    @Test("Only text-entry fields take keyboard focus")
    func excludesNonTextFields() {
        // Gender, date of birth, role and the terms toggle are pickers and a
        // switch. Putting them in the chain would make the keyboard's Next
        // button jump to a control that cannot receive typing.
        for field in [RegistrationField.dateOfBirth, .role, .acceptTerms] {
            #expect(!RegistrationField.focusOrder.contains(field))
        }
    }

    @Test("Each field advances to the one below it")
    func advancesInOrder() {
        #expect(RegistrationField.userName.next == .name)
        #expect(RegistrationField.email.next == .password)
        #expect(RegistrationField.password.next == .confirmPassword)
    }

    @Test("The last text field ends the chain rather than wrapping")
    func lastFieldEndsChain() {
        // Wrapping back to the top would bounce the user to the start of the
        // form when they expect to submit.
        #expect(RegistrationField.phone.next == nil)
    }

    @Test("A field outside the chain has no successor")
    func nonTextFieldHasNoSuccessor() {
        #expect(RegistrationField.role.next == nil)
    }
}

@Suite("First invalid field")
struct FirstInvalidFieldTests {

    @Test("An empty draft points at the first field on screen")
    func emptyDraft() {
        #expect(RegistrationDraft().firstInvalidField() == .userName)
    }

    @Test("Reports the topmost failure, not an arbitrary one")
    func topmostFailure() {
        // Dictionary order is not stable, so returning `errors.first` would
        // scroll somewhere unpredictable. Screen order is what the user expects.
        var draft = RegistrationDraft(
            userName: "john_doe",
            name: "John Doe",
            email: "not-an-email",
            password: "Str0ng!pass",
            confirmPassword: "Str0ng!pass",
            phone: "nonsense",
            dateOfBirth: Date(timeIntervalSince1970: 0),
            role: .employee,
            acceptTerms: true
        )
        #expect(draft.firstInvalidField() == .email)

        draft.email = "john@company.com"
        #expect(draft.firstInvalidField() == .phone)
    }

    @Test("Non-text failures are still reported once the text fields are clean")
    func fallsThroughToPickers() {
        let draft = RegistrationDraft(
            userName: "john_doe",
            name: "John Doe",
            email: "john@company.com",
            password: "Str0ng!pass",
            confirmPassword: "Str0ng!pass",
            phone: "+911234567890",
            dateOfBirth: nil,
            role: nil,
            acceptTerms: false
        )
        #expect(draft.firstInvalidField() == .dateOfBirth)
    }

    @Test("A valid draft has nothing to scroll to")
    func validDraft() {
        let draft = RegistrationDraft(
            userName: "john_doe",
            name: "John Doe",
            email: "john@company.com",
            password: "Str0ng!pass",
            confirmPassword: "Str0ng!pass",
            phone: "+911234567890",
            dateOfBirth: Date(timeIntervalSince1970: 0),
            role: .employee,
            acceptTerms: true
        )
        #expect(draft.firstInvalidField() == nil)
    }
}
