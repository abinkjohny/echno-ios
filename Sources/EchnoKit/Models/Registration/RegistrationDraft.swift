import Foundation

/// What the user has entered on the registration form, and the rules that decide
/// whether it may be submitted.
///
/// A plain value type with no UI in it, so the rules are reachable from tests
/// without a simulator. The screen wraps this in an observable form object and
/// owns presentation; everything that decides *correct* lives here.
///
/// The rules match echno-web's `lib/validators` and the backend's
/// `UserRegistrationDto` constraints, so the same input is not accepted by one
/// client and rejected by the other. Where the two disagree the stricter wins:
/// the backend allows a username of 3–50 characters and echno-web wants 4–20,
/// so 4–20 is enforced.
public struct RegistrationDraft: Sendable, Equatable {

    public var userName: String
    public var name: String
    public var email: String
    public var password: String
    public var confirmPassword: String
    public var phone: String
    public var gender: Gender
    public var dateOfBirth: Date?
    public var role: UserRole?
    public var acceptTerms: Bool

    public init(
        userName: String = "",
        name: String = "",
        email: String = "",
        password: String = "",
        confirmPassword: String = "",
        phone: String = "",
        gender: Gender = .male,
        dateOfBirth: Date? = nil,
        role: UserRole? = nil,
        acceptTerms: Bool = false
    ) {
        self.userName = userName
        self.name = name
        self.email = email
        self.password = password
        self.confirmPassword = confirmPassword
        self.phone = phone
        self.gender = gender
        self.dateOfBirth = dateOfBirth
        self.role = role
        self.acceptTerms = acceptTerms
    }

    // MARK: Rules

    /// The minimum age the backend's terms require.
    public static let minimumAge = 18

    private enum Pattern {
        static let userName = "^[a-zA-Z0-9._-]+$"
        static let name = "^[a-zA-Z\\s'.-]+$"
        static let email = "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$"
        static let phone = "^\\+?[1-9]\\d{7,14}$"
        static let uppercase = "[A-Z]"
        static let lowercase = "[a-z]"
        static let digit = "[0-9]"
        static let special = "[!@#$%^&*(),.?\":{}|<>]"
    }

    /// Every failing field, keyed by field.
    ///
    /// Reports all failures at once rather than stopping at the first, so the
    /// form can mark every bad field in one pass instead of making the user
    /// submit repeatedly to discover them.
    ///
    /// - Returns: A message per invalid field. Empty when the draft may be sent.
    public func validate() -> [RegistrationField: String] {
        var errors: [RegistrationField: String] = [:]

        if userName.isEmpty {
            errors[.userName] = "Username is required"
        } else if userName.count < 4 || userName.count > 20 {
            errors[.userName] = "Username must be between 4 and 20 characters"
        } else if !userName.matches(Pattern.userName) {
            errors[.userName] = "Only letters, numbers, dots, underscores and hyphens"
        }

        if name.isEmpty {
            errors[.name] = "Full name is required"
        } else if name.count < 2 {
            errors[.name] = "Name must be at least 2 characters long"
        } else if !name.matches(Pattern.name) {
            errors[.name] = "Name contains invalid characters"
        }

        if email.isEmpty {
            errors[.email] = "Email is required"
        } else if !email.matches(Pattern.email) {
            errors[.email] = "Invalid email address"
        }

        if let problem = Self.passwordProblem(password) {
            errors[.password] = problem
        }

        if confirmPassword.isEmpty {
            errors[.confirmPassword] = "Confirm password is required"
        } else if confirmPassword != password {
            errors[.confirmPassword] = "Passwords do not match"
        }

        if phone.isEmpty {
            errors[.phone] = "Phone is required"
        } else if !phone.matches(Pattern.phone) {
            errors[.phone] = "Invalid phone number"
        }

        if dateOfBirth == nil { errors[.dateOfBirth] = "Date of birth is required" }
        if role == nil { errors[.role] = "Role is required" }
        if !acceptTerms { errors[.acceptTerms] = "You must accept the terms and conditions" }

        return errors
    }

    /// The topmost invalid field, or `nil` when the draft may be submitted.
    ///
    /// Screen order, not dictionary order: ``validate()`` returns a dictionary,
    /// whose iteration order is unspecified, so taking its first element would
    /// scroll somewhere unpredictable. The user expects to land on the first
    /// problem they would see reading down the form.
    ///
    /// - Returns: The field to scroll to and focus, or `nil` if none failed.
    public func firstInvalidField() -> RegistrationField? {
        let errors = validate()
        return RegistrationField.screenOrder.first { errors[$0] != nil }
    }

    /// The first failing password rule, or `nil` when the password is acceptable.
    ///
    /// Rule order matches echno-web's `lib/validators/password.ts` so the same
    /// password draws the same complaint on either client.
    ///
    /// - Parameter value: The candidate password.
    /// - Returns: A message naming the first unmet rule, or `nil`.
    public static func passwordProblem(_ value: String) -> String? {
        if value.isEmpty { return "Password is required" }
        if value.count < 8 { return "Password must be at least 8 characters long" }
        if !value.matches(Pattern.uppercase) { return "Password must contain at least one uppercase letter" }
        if !value.matches(Pattern.lowercase) { return "Password must contain at least one lowercase letter" }
        if !value.matches(Pattern.digit) { return "Password must contain at least one number" }
        if !value.matches(Pattern.special) { return "Password must contain at least one special character" }
        return nil
    }

    /// How many of the five password rules the current password satisfies.
    ///
    /// Drives the strength meter, which exists so the rules have a shape before
    /// the user submits rather than after.
    public var passwordStrength: Int {
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.matches(Pattern.uppercase) { score += 1 }
        if password.matches(Pattern.lowercase) { score += 1 }
        if password.matches(Pattern.digit) { score += 1 }
        if password.matches(Pattern.special) { score += 1 }
        return score
    }

    /// The span of birth dates the picker offers.
    ///
    /// The upper bound is exactly ``minimumAge`` years before `now`, so someone
    /// whose birthday is tomorrow cannot be selected.
    ///
    /// - Parameter now: The current moment. Injectable so the boundary is testable.
    public static func dateOfBirthRange(now: Date = .now) -> ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let newest = calendar.date(byAdding: .year, value: -minimumAge, to: now) ?? now
        let oldest = calendar.date(byAdding: .year, value: -120, to: now) ?? now
        return oldest...newest
    }
}

extension String {
    /// Whether the whole string satisfies `pattern`.
    fileprivate func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
