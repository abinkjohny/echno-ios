import Foundation

/// The line at the top of Home.
///
/// Here rather than in the view because it is a rule with boundaries and edge
/// cases, and a rule that matters is a rule worth testing — see `CLAUDE.md`
/// § Test-driven development.
public enum Greeting {

    /// The time-of-day phrase for `date`, in the device's own calendar.
    ///
    /// Boundaries are the conventional ones: morning from 05:00, afternoon from
    /// 12:00, evening from 17:00 and through the small hours. Someone checking
    /// in for a 04:00 shift is finishing a night, not starting a morning.
    public static func phrase(
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    /// The phrase with the person's first name, where there is one to use.
    ///
    /// Only words beginning with a letter count, for the same reason
    /// ``initials(of:)`` filters them: registration permits hyphens, dots and
    /// apostrophes, which also admits "---", and "Good morning, ---" reads as a
    /// fault rather than as a missing name.
    public static func line(
        for name: String,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let phrase = phrase(at: date, calendar: calendar)
        guard let first = name
            .split(whereSeparator: \.isWhitespace)
            .first(where: { $0.first?.isLetter == true })
        else { return phrase }
        return "\(phrase), \(first)"
    }
}
