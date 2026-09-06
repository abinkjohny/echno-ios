import Foundation
import Observation
import EchnoKit

/// Observable state for the registration screen.
///
/// Deliberately thin. Every rule about what makes a registration valid lives in
/// ``RegistrationDraft`` in `EchnoKit`, where it is reachable by `swift test`
/// without a simulator. This type owns only what is genuinely presentation:
/// which messages are currently visible, and whether a submit is in flight.
@Observable
final class RegistrationForm {

    /// The values the user has entered.
    private(set) var draft = RegistrationDraft()

    /// Messages shown beneath each field.
    ///
    /// Populated on submit, not on every keystroke — telling someone their email
    /// is malformed while they are still typing it is noise, not help.
    private(set) var errors: [RegistrationField: String] = [:]

    /// True while a registration request is in flight.
    var isSubmitting = false

    /// The field the view should scroll to and focus.
    ///
    /// Set when a submit fails validation and cleared by the view once it has
    /// scrolled, so a second failed submit on the same field scrolls again.
    var scrollTarget: RegistrationField?

    // MARK: Field access
    //
    // Forwarded so the view binds to `form.email` rather than
    // `form.draft.email`, and so editing a field clears its stale message.

    var userName: String {
        get { draft.userName }
        set { draft.userName = newValue; clearError(.userName) }
    }

    var name: String {
        get { draft.name }
        set { draft.name = newValue; clearError(.name) }
    }

    var email: String {
        get { draft.email }
        set { draft.email = newValue; clearError(.email) }
    }

    var password: String {
        get { draft.password }
        set { draft.password = newValue; clearError(.password) }
    }

    var confirmPassword: String {
        get { draft.confirmPassword }
        set { draft.confirmPassword = newValue; clearError(.confirmPassword) }
    }

    var phone: String {
        get { draft.phone }
        set { draft.phone = newValue; clearError(.phone) }
    }

    var gender: Gender {
        get { draft.gender }
        set { draft.gender = newValue }
    }

    var dateOfBirth: Date? {
        get { draft.dateOfBirth }
        set { draft.dateOfBirth = newValue; clearError(.dateOfBirth) }
    }

    var role: UserRole? {
        get { draft.role }
        set { draft.role = newValue; clearError(.role) }
    }

    var acceptTerms: Bool {
        get { draft.acceptTerms }
        set { draft.acceptTerms = newValue; clearError(.acceptTerms) }
    }

    // MARK: Validation

    /// The message to show under `field`, if any.
    func error(for field: RegistrationField) -> String? { errors[field] }

    /// Drops a field's message so a corrected field stops shouting before the
    /// user submits again.
    func clearError(_ field: RegistrationField) {
        guard errors[field] != nil else { return }
        errors[field] = nil
    }

    /// Validates the draft, publishes the messages, and reports whether the form
    /// may be submitted.
    @discardableResult
    func validate() -> Bool {
        errors = draft.validate()
        return errors.isEmpty
    }

    /// The topmost invalid field, in screen order.
    func firstInvalidField() -> RegistrationField? { draft.firstInvalidField() }

    /// How many of the five password rules are currently satisfied.
    var passwordStrength: Int { draft.passwordStrength }

    /// The birth dates the picker offers — no younger than the minimum age.
    var dateOfBirthRange: ClosedRange<Date> { RegistrationDraft.dateOfBirthRange() }
}
