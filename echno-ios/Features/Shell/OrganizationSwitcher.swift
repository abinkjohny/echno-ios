import SwiftUI
import EchnoKit

/// Shows which organization the app is acting in, and lets the user change it.
///
/// This is not decoration. `X-Organization-Id` is a tenant boundary: every
/// request is scoped by it, and the backend rejects a caller who belongs to
/// several organizations and does not say which one they mean. So the active
/// tenant has to be visible at all times — someone looking at a materials list
/// needs to know which site's materials they are.
///
/// The unselected state is a real state, not a loading one. Someone who belongs
/// to several organizations and has not chosen is shown that they must, because
/// the app genuinely cannot act until they do.
struct OrganizationSwitcher: ToolbarContent {

    @Environment(AuthSession.self) private var session
    @Environment(OrganizationStore.self) private var store

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if store.organizations.isEmpty {
                    Label(emptyLabel, systemImage: "building.2")
                } else {
                    Picker("Organization", selection: selection) {
                        ForEach(store.organizations) { organization in
                            Label(organization.name, systemImage: "building.2")
                                .tag(Optional(organization.id))
                        }
                    }
                }
            } label: {
                label
            }
            .disabled(store.organizations.count < 2 && store.selected != nil)
        }
    }

    /// Writes through the session rather than the store: selecting has to reach
    /// the credential provider too, or the next request carries the old tenant.
    private var selection: Binding<Int64?> {
        Binding(
            get: { store.selected?.id },
            set: { id in
                guard let id else { return }
                Task { await session.select(organization: id) }
            }
        )
    }

    private var emptyLabel: String {
        if store.isLoading { "Loading organizations…" }
        else if store.error != nil { "Organizations unavailable" }
        else { "No organizations yet" }
    }

    @ViewBuilder
    private var label: some View {
        if let selected = store.selected {
            // The initials, not the building glyph: with one tenant the glyph
            // says nothing, and with several the point is *which* one.
            Text(selected.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(Echno.Text.brandOnTint)
                .frame(width: Echno.Size.avatar * 0.64, height: Echno.Size.avatar * 0.64)
                .background(Echno.brand.opacity(Echno.Opacity.subtle), in: Circle())
                .accessibilityLabel("Organization: \(selected.name)")
                .accessibilityHint("Switches the organization the app is acting in")
        } else {
            Image(systemName: "building.2")
                .accessibilityLabel(
                    store.organizations.count > 1
                        ? "Choose an organization"
                        : "Switch organization"
                )
        }
    }
}
