import Foundation

/// A top-level place in the app.
///
/// Mirrors echno-web's sidebar so someone moving between the two products does
/// not have to relearn where things are. Icons are SF Symbols chosen to match
/// the *meaning* of echno-web's lucide icons rather than their shape — see
/// `local-docs/ios-action-plan.md` §4.
public enum NavigationDestination: String, CaseIterable, Identifiable, Sendable {
    case home
    case chat
    case projects
    case inspections
    case attendance
    case workforce
    case resources
    case finance
    case thirdParty
    case organizations
    case settings

    public var id: String { rawValue }

    /// Title case, because these are labels rather than prose.
    public var title: String {
        switch self {
        case .home: "Home"
        case .chat: "Chat"
        case .projects: "Projects"
        case .inspections: "Inspections"
        case .attendance: "Attendance"
        case .workforce: "Workforce"
        case .resources: "Resources"
        case .finance: "Finance"
        case .thirdParty: "Third Party"
        case .organizations: "Organizations"
        case .settings: "Settings"
        }
    }

    public var symbol: String {
        switch self {
        case .home: "house"                          // lucide: Home
        case .chat: "bubble.left.and.bubble.right"   // lucide: MessageSquare
        case .projects: "folder"                     // lucide: FolderKanban
        case .inspections: "checkmark.seal"          // lucide: ClipboardCheck
        case .attendance: "clock"                    // lucide: Clock
        case .workforce: "person.2"                  // lucide: Users
        case .resources: "shippingbox"               // lucide: Package
        case .finance: "indianrupeesign.circle"      // lucide: Wallet
        case .thirdParty: "building.2"               // lucide: Building2
        case .organizations: "building.columns"      // lucide: Landmark
        case .settings: "gearshape"                  // lucide: Settings
        }
    }
}

/// A group of destinations in the sidebar.
public struct NavigationSection: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let destinations: [NavigationDestination]

    public init(id: String, title: String, destinations: [NavigationDestination]) {
        self.id = id
        self.title = title
        self.destinations = destinations
    }

    /// The sidebar, in order.
    ///
    /// Matches `SIDEBAR_SECTIONS` in echno-web's `nav/sections.ts`. Every
    /// destination appears in exactly one section — a test enforces that,
    /// because a destination in two places shows twice and one in none is
    /// unreachable, and neither is visible without looking.
    public static let all: [NavigationSection] = [
        NavigationSection(id: "overview", title: "Overview", destinations: [.home, .chat]),
        NavigationSection(id: "projects", title: "Projects", destinations: [.projects]),
        NavigationSection(id: "inspections", title: "Inspections", destinations: [.inspections]),
        NavigationSection(id: "workforce", title: "Workforce", destinations: [.attendance, .workforce]),
        NavigationSection(
            id: "operations",
            title: "Operations",
            destinations: [.resources, .finance, .thirdParty]
        ),
        NavigationSection(id: "system", title: "System", destinations: [.organizations, .settings])
    ]
}

extension NavigationDestination {

    /// What the phone's tab bar shows.
    ///
    /// Four, not five: iOS collapses everything past the fifth tab into a system
    /// More tab, so the last slot is spent on our own More rather than losing
    /// control of what gets buried.
    ///
    /// The choice is field-first. The reason this app exists on a phone is site
    /// work, so attendance is one tap from launch — behind a menu it would be
    /// the wrong product. Finance and inspections are iPad-and-desk work and sit
    /// in More.
    public static let phoneTabs: [NavigationDestination] = [
        .home, .attendance, .projects, .workforce
    ]

    /// Everything the tab bar does not show, in sidebar order.
    ///
    /// Derived rather than listed, so adding a destination cannot leave it
    /// unreachable on the phone.
    public static var moreDestinations: [NavigationDestination] {
        NavigationSection.all
            .flatMap(\.destinations)
            .filter { !phoneTabs.contains($0) }
    }
}
