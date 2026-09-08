import Foundation
import Testing
#if canImport(AppKit)
import AppKit
#endif
@testable import EchnoKit

@Suite("Navigation structure")
struct NavigationStructureTests {

    @Test("The sections match echno-web's sidebar, in the same order")
    func sectionsMatchWeb() {
        // Source: echno-web nav/sections.ts SIDEBAR_SECTIONS. Someone moving
        // between the two products should not have to relearn where things are.
        #expect(NavigationSection.all.map(\.id) == [
            "overview", "projects", "inspections", "workforce", "operations", "system"
        ])
        #expect(NavigationSection.all.map(\.title) == [
            "Overview", "Projects", "Inspections", "Workforce", "Operations", "System"
        ])
    }

    @Test("Every destination belongs to exactly one section")
    func destinationsArePartitioned() {
        // A destination in two sections appears twice in the sidebar; one in
        // none is unreachable. Both are easy to introduce and invisible until
        // someone looks.
        let placed = NavigationSection.all.flatMap(\.destinations)
        #expect(Set(placed) == Set(NavigationDestination.allCases))
        #expect(placed.count == NavigationDestination.allCases.count)
    }

    @Test("Every destination has a title and an icon")
    func destinationsAreComplete() {
        for destination in NavigationDestination.allCases {
            #expect(!destination.title.isEmpty)
            #expect(!destination.symbol.isEmpty)
        }
    }

    @Test("Titles are title case, per the copy convention")
    func titlesAreTitleCase() {
        // Nav items are labels, not prose. Lowercase articles and short
        // prepositions are allowed anywhere but the first word.
        let lowercaseAllowed: Set<String> = ["a", "an", "the", "and", "or", "of", "in", "to", "for"]
        for destination in NavigationDestination.allCases {
            for (index, word) in destination.title.split(separator: " ").enumerated() {
                let word = String(word)
                if index > 0, lowercaseAllowed.contains(word.lowercased()) { continue }
                #expect(
                    word.first?.isUppercase == true,
                    "\(destination.title) — \"\(word)\" should be capitalised"
                )
            }
        }
    }
}

@Suite("Navigation icons")
struct NavigationIconTests {

    #if canImport(AppKit)
    @Test("Every icon is a real SF Symbol")
    func symbolsExist() {
        // A misspelled symbol name does not throw or warn — it renders as blank
        // space, and the first anyone knows is a screenshot with a hole in it.
        // AppKit resolves the same symbol set, so this catches typos on macOS
        // where `swift test` runs.
        for destination in NavigationDestination.allCases {
            #expect(
                NSImage(systemSymbolName: destination.symbol, accessibilityDescription: nil) != nil,
                "\(destination.title) uses \"\(destination.symbol)\", which is not an SF Symbol"
            )
        }
    }
    #endif
}

@Suite("Compact navigation")
struct CompactNavigationTests {

    @Test("The phone shows at most five tabs")
    func tabLimit() {
        // iOS collapses anything past the fifth into a system More tab, which
        // buries whatever lands there. Choosing the five deliberately is the
        // whole point.
        #expect(NavigationDestination.phoneTabs.count <= 5)
    }

    @Test("The phone tabs are real destinations, not a separate list")
    func tabsAreDestinations() {
        for tab in NavigationDestination.phoneTabs {
            #expect(NavigationDestination.allCases.contains(tab))
        }
    }

    @Test("The field-first destinations are on the phone's tab bar")
    func fieldWorkIsReachableInOneTap() {
        // The reason this app exists on a phone is site work. Attendance behind
        // a More menu would be the wrong product.
        #expect(NavigationDestination.phoneTabs.contains(.home))
        #expect(NavigationDestination.phoneTabs.contains(.attendance))
        #expect(NavigationDestination.phoneTabs.contains(.projects))
    }

    @Test("Everything not on the tab bar is still reachable from More")
    func moreCoversTheRemainder() {
        let reachable = Set(NavigationDestination.phoneTabs).union(NavigationDestination.moreDestinations)
        #expect(reachable == Set(NavigationDestination.allCases))
    }

    @Test("No destination is both a tab and in More")
    func noDuplicates() {
        let overlap = Set(NavigationDestination.phoneTabs)
            .intersection(NavigationDestination.moreDestinations)
        #expect(overlap.isEmpty)
    }
}
