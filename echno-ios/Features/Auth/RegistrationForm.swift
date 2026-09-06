import Foundation

/// The roles offered at registration.
///
/// Mirrors `UserRole` in the backend (`user/enums/UserRole.java`). The wire
/// value is the raw case name; the label is what the picker shows.
enum UserRole: String, CaseIterable, Identifiable, Sendable {
    case owner = "OWNER"
    case coFounder = "CO_FOUNDER"
    case hrManager = "HR_MANAGER"
    case employee = "EMPLOYEE"
    case student = "STUDENT"
    case management = "MANAGEMENT"
    case administrator = "ADMINISTRATOR"

    var id: String { rawValue }

    var label: String {
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

enum Gender: String, CaseIterable, Identifiable, Sendable {
    case male = "Male"
    case female = "Female"
    case other = "Other"

    var id: String { rawValue }
}

/// Which field a validation message belongs to.
enum RegistrationField: Hashable {
    case userName, name, email, password, confirmPassword, phone, dateOfBirth, role, acceptTerms
}

/// Form state and validation for the registration screen.
///
/// The rules match echno-web's `lib/validators` and the backend's
/// `UserRegistrationDto` constraints, so a form that passes here is not
/// rejected differently on one client than the other. Where the two disagree
/// the stricter one wins — echno-web requires a username of 4–20 characters,
/// the backend allows 3–50, so 4–20 is enforced.
@Observable
final class RegistrationForm {

    var userName = ""
    var name = ""
    var email = ""
    var password = ""
    var confirmPassword = ""
    var phone = ""
    var gender: Gender = .male
    var dateOfBirth: Date?
    var role: UserRole?
    var acceptTerms = false

    /// Messages shown under each field. Populated on submit and cleared as the
    /// offending field is edited.
    private(set) var errors: [RegistrationField: String] = [:]

    var isSubmitting = false

    /// The oldest and youngest dates of birth the picker allows.
    /// Registration requires 18+, matching echno-web.
    static let minimumAge = 18
    var dateOfBirthRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date.now
        let newest = calendar.date(byAdding: .year, value: -Self.minimumAge, to: now) ?? now
        let oldest = calendar.date(byAdding: .year, value: -120, to: now) ?? now
        return oldest...newest
    }

    func error(for field: RegistrationField) -> String? { errors[field] }

    /// Clears a field's message once the user edits it, so a corrected field
    /// stops shouting before they submit again.
    func clearError(_ field: RegistrationField) {
        guard errors[field] != nil else { return }
        errors[field] = nil
    }

    /// Validates every field, populates ``errors``, and reports whether the
    /// form may be submitted.
    @discardableResult
    func validate() -> Bool {
        var found: [RegistrationField: String] = [:]

        if userName.isEmpty {
            found[.userName] = "Username is required"
        } else if userName.count < 4 || userName.count > 20 {
            found[.userName] = "Username must be between 4 and 20 characters"
        } else if userName.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) == nil {
            found[.userName] = "Only letters, numbers, dots, underscores and hyphens"
        }

        if name.isEmpty {
            found[.name] = "Full name is required"
        } else if name.count < 2 {
            found[.name] = "Name must be at least 2 characters long"
        } else if name.range(of: "^[a-zA-Z\\s'.-]+$", options: .regularExpression) == nil {
            found[.name] = "Name contains invalid characters"
        }

        if email.isEmpty {
            found[.email] = "Email is required"
        } else if email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) == nil {
            found[.email] = "Invalid email address"
        }

        if let message = Self.passwordProblem(password) {
            found[.password] = message
        }

        if confirmPassword.isEmpty {
            found[.confirmPassword] = "Confirm password is required"
        } else if confirmPassword != password {
            found[.confirmPassword] = "Passwords do not match"
        }

        if phone.isEmpty {
            found[.phone] = "Phone is required"
        } else if phone.range(of: "^\\+?[1-9]\\d{7,14}$", options: .regularExpression) == nil {
            found[.phone] = "Invalid phone number"
        }

        if dateOfBirth == nil {
            found[.dateOfBirth] = "Date of birth is required"
        }

        if role == nil {
            found[.role] = "Role is required"
        }

        if !acceptTerms {
            found[.acceptTerms] = "You must accept the terms and conditions"
        }

        errors = found
        return found.isEmpty
    }

    /// The first failing password rule, or `nil` when the password is good.
    ///
    /// Rules and their order match echno-web's `lib/validators/password.ts`, so
    /// the same password produces the same complaint on both clients.
    static func passwordProblem(_ value: String) -> String? {
        if value.isEmpty { return "Password is required" }
        if value.count < 8 { return "Password must be at least 8 characters long" }
        if value.range(of: "[A-Z]", options: .regularExpression) == nil {
            return "Password must contain at least one uppercase letter"
        }
        if value.range(of: "[a-z]", options: .regularExpression) == nil {
            return "Password must contain at least one lowercase letter"
        }
        if value.range(of: "[0-9]", options: .regularExpression) == nil {
            return "Password must contain at least one number"
        }
        if value.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) == nil {
            return "Password must contain at least one special character"
        }
        return nil
    }

    /// How far along the password is, for the strength meter — the count of
    /// satisfied rules out of five.
    var passwordStrength: Int {
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[a-z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil { score += 1 }
        return score
    }
}
