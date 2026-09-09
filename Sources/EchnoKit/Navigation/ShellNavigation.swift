import Foundation

/// Which tab the phone's tab bar has selected.
///
/// A separate type from ``NavigationDestination`` on purpose. More is a tab but
/// not a destination — it is a list of them — so tagging it with a real
/// destination conflates the two, and whatever destination gets borrowed for the
/// tag becomes what the sidebar shows after a layout change.
public enum PhoneTab: Hashable, Sendable {
    case destination(NavigationDestination)
    case more
}

/// Where the app is, in terms both layouts can express.
///
/// The compact and regular shells present the same place differently: a tab bar
/// with a More list, or a sidebar. Keeping one piece of truth and deriving each
/// presentation from it is what lets a device rotate without losing the user's
/// place.
///
/// ``destination`` is that truth — the thing the user is actually looking at.
/// ``phoneTab`` and ``morePath`` are how the phone expresses it.
public struct ShellNavigation: Sendable, Equatable {

    /// What the user is looking at. Both layouts render this.
    public private(set) var destination: NavigationDestination

    /// Which tab is active on the phone.
    ///
    /// Not always derivable from ``destination``: tapping More opens a list
    /// without choosing anything, so the tab moves while the destination does
    /// not.
    public private(set) var phoneTab: PhoneTab

    /// Whether More has pushed past its root, and to what.
    private var isShowingDestinationInMore: Bool

    public init(destination: NavigationDestination = .home) {
        self.destination = destination
        if NavigationDestination.phoneTabs.contains(destination) {
            self.phoneTab = .destination(destination)
            self.isShowingDestinationInMore = false
        } else {
            self.phoneTab = .more
            self.isShowingDestinationInMore = true
        }
    }

    /// What More's navigation stack should contain.
    public var morePath: [NavigationDestination] {
        isShowingDestinationInMore ? [destination] : []
    }

    /// The user tapped a tab.
    ///
    /// Tapping More chooses nothing — it shows a list — so the destination is
    /// left alone. Moving it would jump the user somewhere they never asked for
    /// the moment the device rotated.
    public mutating func selectTab(_ tab: PhoneTab) {
        phoneTab = tab
        switch tab {
        case .destination(let chosen):
            destination = chosen
            isShowingDestinationInMore = false
        case .more:
            isShowingDestinationInMore = false
        }
    }

    /// The user chose something from the More list.
    public mutating func selectFromMore(_ chosen: NavigationDestination) {
        destination = chosen
        phoneTab = .more
        isShowingDestinationInMore = true
    }

    /// The user chose something in the sidebar.
    ///
    /// Maps back onto the phone's layout so returning to compact lands on the
    /// screen they were reading rather than at the More root.
    public mutating func selectFromSidebar(_ chosen: NavigationDestination) {
        destination = chosen
        if NavigationDestination.phoneTabs.contains(chosen) {
            phoneTab = .destination(chosen)
            isShowingDestinationInMore = false
        } else {
            phoneTab = .more
            isShowingDestinationInMore = true
        }
    }

    /// More's navigation stack changed — usually a swipe back.
    public mutating func setMorePath(_ path: [NavigationDestination]) {
        if let last = path.last {
            destination = last
            phoneTab = .more
            isShowingDestinationInMore = true
        } else {
            isShowingDestinationInMore = false
        }
    }
}
