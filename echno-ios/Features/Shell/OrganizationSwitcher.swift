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
/// - Note: The list is a placeholder until the `organization` module lands in
///   Wave 1. `GET /api/v1/user/web/{userId}/organizations` supplies it; the
///   switcher's job here is to hold the position and the meaning.
struct OrganizationSwitcher: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Organization") {
                    // Wave 1 replaces this with the user's real memberships.
                    Label("No organization selected", systemImage: "building.2")
                }
            } label: {
                Image(systemName: "building.2")
                    .accessibilityLabel("Switch organization")
            }
        }
    }
}
