import Foundation

/// The roles a user may pick when registering.
///
/// Mirrors `UserRole` in the backend (`user/enums/UserRole.java`). The document
/// types `UserRegistrationDto.role` as a bare `String` with no enum, so this
/// cannot be generated and is kept in step by a test that asserts the wire
/// values. If the backend adds a role, that test fails first.
public enum UserRole: String, CaseIterable, Identifiable, Sendable {
    case owner = "OWNER"
    case coFounder = "CO_FOUNDER"
    case hrManager = "HR_MANAGER"
    case employee = "EMPLOYEE"
    case student = "STUDENT"
    case management = "MANAGEMENT"
    case administrator = "ADMINISTRATOR"

    public var id: String { rawValue }

    /// The label shown in the UI. Never sent to the backend — ``rawValue`` is.
    public var label: String {
        switch self {
        case .owner: "Owner"
        case .coFounder: "Co-Founder"
        case .hrManager: "HR Manager"
        case .employee: "Employee"
        case .student: "Student"
        case .management: "Management"
        case .administrator: "Administrator"
        }
    }
}

/// Gender, as the backend spells it.
///
/// `UserRegistrationDto.gender` is a required free-text `String`; these are the
/// three values echno-web sends, so the two clients stay consistent.
public enum Gender: String, CaseIterable, Identifiable, Sendable {
    case male = "Male"
    case female = "Female"
    case other = "Other"

    public var id: String { rawValue }
}

/// A field on the registration form.
///
/// Used to key validation messages, to drive the keyboard's Next button, and to
/// decide which field to scroll to when a submit fails. Declared in the order
/// the fields appear on screen — ``screenOrder`` depends on that.
public enum RegistrationField: Hashable, Sendable, CaseIterable {
    case userName
    case name
    case email
    case password
    case confirmPassword
    case phone
    case gender
    case dateOfBirth
    case role
    case acceptTerms

    /// Every field, top to bottom as laid out on screen.
    ///
    /// Screen order rather than declaration order is what a scroll-to-error
    /// should follow, and `allCases` already matches it — but relying on that
    /// silently would break the moment someone reorders the enum for tidiness.
    public static var screenOrder: [RegistrationField] { allCases }

    /// The text-entry fields, in the order the keyboard should walk them.
    ///
    /// Pickers and the terms switch are excluded: a Next button that jumped to
    /// a control which cannot receive typing would dismiss the keyboard and
    /// look broken.
    public static let focusOrder: [RegistrationField] = [
        .userName, .name, .email, .password, .confirmPassword, .phone
    ]

    /// The next field the keyboard's Next button should move to.
    ///
    /// `nil` for the final text field, so the keyboard shows Done and the user
    /// is not bounced back to the top of a ten-field form.
    public var next: RegistrationField? {
        guard
            let index = Self.focusOrder.firstIndex(of: self),
            index + 1 < Self.focusOrder.count
        else { return nil }
        return Self.focusOrder[index + 1]
    }

    /// Whether this field takes keyboard focus.
    public var isTextEntry: Bool { Self.focusOrder.contains(self) }
}
