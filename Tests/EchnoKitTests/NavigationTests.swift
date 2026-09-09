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

@Suite("Shell navigation state")
struct ShellNavigationTests {

    @Test("Starts on Home, with Home's tab active")
    func initialState() {
        let navigation = ShellNavigation()
        #expect(navigation.destination == .home)
        #expect(navigation.phoneTab == .destination(.home))
        #expect(navigation.morePath.isEmpty)
    }

    @Test("Choosing a tab makes it both the tab and the destination")
    func selectingATab() {
        var navigation = ShellNavigation()
        navigation.selectTab(.destination(.attendance))
        #expect(navigation.destination == .attendance)
        #expect(navigation.phoneTab == .destination(.attendance))
        #expect(navigation.morePath.isEmpty)
    }

    @Test("Opening More does not change what is selected")
    func openingMore() {
        // More is a list, not a place. Tapping it chooses nothing yet, so the
        // destination must not move — otherwise rotating would jump the user
        // somewhere they never asked for.
        var navigation = ShellNavigation()
        navigation.selectTab(.more)
        #expect(navigation.phoneTab == .more)
        #expect(navigation.destination == .home)
        #expect(navigation.morePath.isEmpty)
    }

    @Test("A destination chosen inside More survives a switch to the sidebar")
    func moreSelectionSurvivesLayoutChange() {
        // The bug this guards: the More tab used to be tagged with a real
        // destination, and pushing inside it left the shared selection on that
        // tag. Rotating a Plus or Max iPhone to landscape switches to the
        // regular-width sidebar, which then showed Settings instead of what the
        // user was actually reading.
        var navigation = ShellNavigation()
        navigation.selectTab(.more)
        navigation.selectFromMore(.finance)

        #expect(navigation.destination == .finance)
        #expect(navigation.phoneTab == .more)
        #expect(navigation.morePath == [.finance])
    }

    @Test("Choosing from the sidebar puts the phone on the right tab")
    func sidebarSelectionMapsToATab() {
        var navigation = ShellNavigation()
        navigation.selectFromSidebar(.projects)
        #expect(navigation.phoneTab == .destination(.projects))
        #expect(navigation.morePath.isEmpty)
    }

    @Test("A sidebar choice outside the tab bar lands in More, already pushed")
    func sidebarSelectionOutsideTabsOpensMore() {
        // Symmetry with the case above: going regular → compact must land the
        // user on the screen they were reading, not at the More root.
        var navigation = ShellNavigation()
        navigation.selectFromSidebar(.inspections)
        #expect(navigation.phoneTab == .more)
        #expect(navigation.morePath == [.inspections])
    }

    @Test("Popping back to the More root leaves the destination reachable")
    func poppingMore() {
        var navigation = ShellNavigation()
        navigation.selectFromMore(.finance)
        navigation.setMorePath([])
        #expect(navigation.phoneTab == .more)
        #expect(navigation.morePath.isEmpty)
    }

    @Test("Leaving More for a tab clears what More was showing")
    func leavingMore() {
        var navigation = ShellNavigation()
        navigation.selectFromMore(.finance)
        navigation.selectTab(.destination(.home))
        #expect(navigation.destination == .home)
        #expect(navigation.morePath.isEmpty)
    }

    @Test("Every destination round-trips between the two layouts", arguments: NavigationDestination.allCases)
    func everyDestinationRoundTrips(destination: NavigationDestination) {
        // Whatever the sidebar can select, the phone must be able to show — and
        // show the same thing back.
        var navigation = ShellNavigation()
        navigation.selectFromSidebar(destination)
        #expect(navigation.destination == destination)

        var returned = ShellNavigation()
        switch navigation.phoneTab {
        case .destination(let tab): returned.selectTab(.destination(tab))
        case .more: returned.selectFromMore(destination)
        }
        #expect(returned.destination == destination)
    }
}
