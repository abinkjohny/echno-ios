import SwiftUI
import EchnoKit

/// The signed-in app, laid out for whatever space it has.
///
/// One structure, two presentations. A `TabView` when compact and a
/// `NavigationSplitView` when regular — not a hamburger, which is a web pattern
/// that hides the entire information architecture behind a button and gives up
/// the platform's back gesture.
///
/// Both read the same ``NavigationSection/all``, so a destination added there
/// appears in both without touching this file.
struct AppShell: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AuthSession.self) private var session
    @State private var navigation = ShellNavigation()

    var body: some View {
        Group {
            if sizeClass == .regular {
                SidebarShell(navigation: $navigation)
            } else {
                TabShell(navigation: $navigation)
            }
        }
        // The session owns the store; the shell publishes it so screens depend
        // on the data they need rather than reaching through the session.
        .environment(session.users)
    }
}

/// iPad, and iPhone in landscape on the larger devices.
private struct SidebarShell: View {
    @Binding var navigation: ShellNavigation
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // iOS's List takes an optional selection; a nil write is a
            // deselection, which the shell has no state for — there is always a
            // detail on screen — so it is ignored rather than modelled.
            List(selection: Binding(
                get: { Optional(navigation.destination) },
                set: { if let new = $0 { navigation.selectFromSidebar(new) } }
            )) {
                ForEach(NavigationSection.all) { section in
                    Section(section.title) {
                        ForEach(section.destinations) { destination in
                            Label(destination.title, systemImage: destination.symbol)
                                .tag(destination)
                        }
                    }
                }
            }
            .navigationTitle("Echno")
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                DestinationView(destination: navigation.destination)
                    // On the detail, not the sidebar. iPad collapses the
                    // sidebar in portrait, and the active tenant has to stay
                    // visible — someone reading a materials list needs to know
                    // whose materials they are.
                    .toolbar { OrganizationSwitcher() }
            }
        }
    }
}

/// iPhone. Four tabs plus More, so the fifth slot is ours rather than the
/// system's — see ``NavigationDestination/phoneTabs``.
private struct TabShell: View {
    @Binding var navigation: ShellNavigation

    /// More is tagged `.more`, not a borrowed destination — see ``PhoneTab``.
    private var tab: Binding<PhoneTab> {
        Binding(get: { navigation.phoneTab }, set: { navigation.selectTab($0) })
    }

    private var morePath: Binding<[NavigationDestination]> {
        Binding(get: { navigation.morePath }, set: { navigation.setMorePath($0) })
    }

    var body: some View {
        TabView(selection: tab) {
            ForEach(NavigationDestination.phoneTabs) { destination in
                NavigationStack {
                    DestinationView(destination: destination)
                        .toolbar { OrganizationSwitcher() }
                }
                .tabItem { Label(destination.title, systemImage: destination.symbol) }
                .tag(PhoneTab.destination(destination))
            }

            NavigationStack(path: morePath) {
                MoreView()
                    .navigationDestination(for: NavigationDestination.self) { destination in
                        DestinationView(destination: destination)
                            .toolbar { OrganizationSwitcher() }
                    }
            }
            .tabItem { Label("More", systemImage: "ellipsis") }
            .tag(PhoneTab.more)
        }
    }
}

/// The remainder of the sections, as a grouped list.
///
/// Grouped by section rather than flattened, so the phone's More and the iPad's
/// sidebar describe the same shape.
private struct MoreView: View {

    private var sections: [NavigationSection] {
        NavigationSection.all.compactMap { section in
            let remaining = section.destinations.filter {
                !NavigationDestination.phoneTabs.contains($0)
            }
            guard !remaining.isEmpty else { return nil }
            return NavigationSection(id: section.id, title: section.title, destinations: remaining)
        }
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.destinations) { destination in
                        // Value-based, so the push goes through the bound path
                        // and the shared state learns where the user went.
                        NavigationLink(value: destination) {
                            Label(destination.title, systemImage: destination.symbol)
                        }
                    }
                }
            }
        }
        .navigationTitle("More")
    }
}

/// Stands in until each module's screen lands in its wave.
private struct DestinationView: View {
    let destination: NavigationDestination

    var body: some View {
        if destination == .home {
            HomeView()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.symbol)
        } description: {
            Text("This section arrives with its module.")
        }
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("iPhone") {
    AppShell().environment(AuthSession())
}

#Preview("Regular width — sidebar") {
    AppShell()
        .environment(AuthSession())
        .environment(\.horizontalSizeClass, .regular)
}
