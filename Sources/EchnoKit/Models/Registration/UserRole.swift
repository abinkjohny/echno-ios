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

/// A field on the registration form, used to key validation messages.
public enum RegistrationField: Hashable, Sendable, CaseIterable {
    case userName
    case name
    case email
    case password
    case confirmPassword
    case phone
    case dateOfBirth
    case role
    case acceptTerms
}
