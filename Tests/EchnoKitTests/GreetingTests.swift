import Foundation
import Testing
@testable import EchnoKit

@Suite("Greeting")
struct GreetingTests {

    /// Builds a date at a given local hour, so the expectation is derived from
    /// the same calendar the code reads rather than from a fixed timestamp that
    /// would mean a different hour in every zone the app ships to.
    private func at(hour: Int) throws -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return try #require(calendar.date(byAdding: .hour, value: hour, to: today))
    }

    @Test(
        "The greeting follows the local hour",
        arguments: [(0, "Good evening"), (4, "Good evening"), (5, "Good morning"),
                    (11, "Good morning"), (12, "Good afternoon"), (16, "Good afternoon"),
                    (17, "Good evening"), (23, "Good evening")]
    )
    func followsTheHour(hour: Int, expected: String) throws {
        #expect(Greeting.phrase(at: try at(hour: hour)) == expected)
    }

    @Test("A first name is used when there is one")
    func usesTheFirstName() throws {
        #expect(Greeting.line(for: "Ravi Kumar", at: try at(hour: 9)) == "Good morning, Ravi")
    }

    @Test("A name with no usable word greets without one")
    func fallsBackWithoutAName() throws {
        // "---" passes registration's validator, and "Good morning, ---" reads
        // as a bug. The greeting still works; it just stops short.
        #expect(Greeting.line(for: "---", at: try at(hour: 9)) == "Good morning")
        #expect(Greeting.line(for: "", at: try at(hour: 9)) == "Good morning")
    }

    @Test("A single-word name is used whole")
    func singleWordName() throws {
        #expect(Greeting.line(for: "Ravi", at: try at(hour: 14)) == "Good afternoon, Ravi")
    }
}
