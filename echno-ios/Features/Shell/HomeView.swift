import SwiftUI
import EchnoKit

/// The signed-in landing screen.
///
/// Built on what the app actually knows: who is signed in, and which
/// organizations they belong to. Attendance, project and task summaries arrive
/// with their modules — echno-web's dashboard fills those tiles from
/// `mock-data`, and copying that here would make the screen look finished while
/// telling the user nothing true. A section appears when its module can feed it.
struct HomeView: View {

    @Environment(AuthSession.self) private var session
    @Environment(UserStore.self) private var store
    @Environment(OrganizationStore.self) private var organizations
    @Environment(\.openURL) private var openURL

    /// Whether the invite-code sheet is up.
    @State private var isJoining = false

    var body: some View {
        List {
            Section { greeting }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            Section("Profile") {
                switch (store.currentUser, store.error) {
                case (let user?, _): profile(user)
                case (nil, let error?): failure(error)
                case (nil, nil): placeholder
                }
            }
            .echnoRow()

            organizationSection

            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
            .echnoRow()
        }
        .navigationTitle("Home")
        // Inline, because the greeting below is this screen's header. Left
        // large, the two stack and the eye has to pick which one is the title —
        // and "Home" is the weaker of the pair: the tab bar already says it.
        .navigationBarTitleDisplayMode(.inline)
        .echnoScreen()
        .refreshable { await reload() }
        .task { await load() }
        // Nothing to do on dismissal: a successful join adopts the organization
        // into the store, and the section is driven by that rather than by
        // anything this screen has to be told.
        .sheet(isPresented: $isJoining) { JoinOrganizationSheet() }
    }

    // MARK: Loading

    /// The user first, then the organizations: the memberships endpoint is
    /// keyed by user id, so there is nothing to ask for until the profile has
    /// arrived. Sequential by necessity, not by preference.
    private func load() async {
        await store.load()
        await session.loadOrganizations()
    }

    private func reload() async {
        await store.reload()
        await session.loadOrganizations()
    }

    // MARK: Content

    @ViewBuilder
    private var greeting: some View {
        VStack(alignment: .leading, spacing: Echno.Space.xs) {
            Text(Greeting.line(for: store.currentUser?.name ?? ""))
                .font(.echnoScreenTitle)
                .foregroundStyle(Echno.foreground)
            if let organization = organizations.selected {
                Text(organization.name)
                    .font(.subheadline)
                    .foregroundStyle(Echno.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Echno.Space.md)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var organizationSection: some View {
        Section {
            if organizations.isLoading && organizations.organizations.isEmpty {
                Text("Loading your organizations…")
                    .font(.subheadline)
                    .foregroundStyle(Echno.mutedForeground)
            } else if let error = organizations.error {
                failure(error)
            } else if organizations.organizations.isEmpty {
                noMemberships
            } else {
                ForEach(organizations.organizations) { organization in
                    organizationRow(organization)
                }
            }
        } header: {
            Text("Organizations")
        } footer: {
            // Shown only when it is true and actionable: several memberships,
            // none chosen. The app cannot scope a request until one is.
            if organizations.selected == nil && organizations.organizations.count > 1 {
                Text("Choose an organization to start working in.")
            }
        }
        .echnoRow()
    }

    /// Creating and joining an organization are web-console only, so this says
    /// where to go instead of offering a button that cannot work. An empty
    /// state that names no next step is a dead end, and the one thing someone
    /// in it needs is the next step.
    /// The state a user is in between registering and belonging anywhere.
    ///
    /// Joining and creating are not the same capability, and the copy must not
    /// merge them. A user can join from the app: `validateInviteCode`
    /// (`POST /api/v1/invitation/web/validate/userId/{userId}`) is authorized
    /// with `isSelfUser(#userId)`, and `TenantFilter` runs a caller holding no
    /// `ORG_MEMBER_` authority unscoped precisely so invite-code redemption can
    /// get them out of this state. Creating is `organization:admin` only, so it
    /// stays in the web console.
    ///
    /// Two actions, because the two capabilities are not the same. Joining is
    /// primary: it is the one the app can finish, and the one a user who was
    /// sent a code is here to do. Opening the console is secondary and exists
    /// because creating an organization cannot be done anywhere else.
    private var noMemberships: some View {
        VStack(alignment: .leading, spacing: Echno.Space.md) {
            Text("You are not a member of any organization yet.")
                .font(.subheadline)
                .foregroundStyle(Echno.mutedForeground)
            Text("Join one with an invite code from its administrator, or create a new organization in the Echno web console.")
                .font(.footnote)
                .foregroundStyle(Echno.mutedForeground)

            EchnoPrimaryButton(title: "Enter Invite Code") { isJoining = true }

            EchnoSecondaryButton(title: "Open the Web Console", systemImage: "arrow.up.forward.square") {
                openURL(EchnoConfiguration.webConsole)
            }
            .accessibilityHint("Opens the Echno web console in your browser, where organizations are created")
        }
        .padding(.vertical, Echno.Space.xs)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func organizationRow(_ organization: Organization) -> some View {
        Button {
            Task { await session.select(organization: organization.id) }
        } label: {
            HStack(spacing: Echno.Space.lg) {
                EchnoAvatar(initials: organization.initials)
                VStack(alignment: .leading, spacing: Echno.Space.hairline) {
                    Text(organization.name)
                        .font(.body)
                        .foregroundStyle(Echno.foreground)
                    if !organization.isActive {
                        Text("Inactive")
                            .font(.caption)
                            .foregroundStyle(Echno.Text.warning)
                    }
                }
                Spacer()
                if organizations.selected?.id == organization.id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Echno.Text.brand)
                }
            }
        }
        .accessibilityAddTraits(organizations.selected?.id == organization.id ? [.isSelected] : [])
    }

    private func profile(_ user: User) -> some View {
        HStack(spacing: Echno.Space.lg) {
            EchnoAvatar(initials: user.initials)
            VStack(alignment: .leading, spacing: Echno.Space.xs) {
                Text(user.name).font(.headline)
                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let role = user.role {
                    Text(role.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Echno.Text.brand)
                }
            }
            Spacer()
        }
        .padding(.vertical, Echno.Space.xs)
        .accessibilityElement(children: .combine)
    }

    /// Held as state by the store, presented here — the store owns data, the
    /// view owns feedback.
    private func failure(_ error: any Error) -> some View {
        VStack(alignment: .leading, spacing: Echno.Space.md) {
            Label(
                (error as? LocalizedError)?.errorDescription ?? "Could not load your profile.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.subheadline)
            .foregroundStyle(Echno.destructive)

            Button("Try Again") { Task { await reload() } }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, Echno.Space.xs)
    }

    /// Redacted rather than a spinner: the row keeps its shape, so the screen
    /// does not jump when the real name arrives.
    private var placeholder: some View {
        HStack(spacing: Echno.Space.lg) {
            EchnoAvatar(initials: "")
            VStack(alignment: .leading, spacing: Echno.Space.xs) {
                Text("Loading name").font(.headline)
                Text("loading@example.com").font(.subheadline)
            }
            Spacer()
        }
        .padding(.vertical, Echno.Space.xs)
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading your profile")
    }
}


// MARK: - Previews
//
// HomeView takes both stores from the environment rather than reaching through
// the session, so every state it can be in is reachable here. Without that, a
// multi-organization account could only be seen by signing in as one.

private struct PreviewLoader: UserLoading {
    var result: Result<User, any Error>
    func currentUser() async throws -> User {
        if case .failure = result { try await Task.sleep(for: .milliseconds(1)) }
        return try result.get()
    }
}

private struct PreviewOrganizations: OrganizationLoading {
    var result: Result<[Organization], any Error>
    func organizations(forUser id: Int64) async throws -> [Organization] { try result.get() }
}

private let previewUser = User(
    id: 42,
    name: "Ravi Kumar",
    email: "ravi.kumar@echno.in",
    phone: "+911234567890",
    role: .employee
)

@MainActor
private func homePreview(
    user: Result<User, any Error> = .success(previewUser),
    organizations: Result<[Organization], any Error> = .success([
        Organization(id: 7, name: "Tornotron Constructions"),
        Organization(id: 8, name: "Harbour Works", isActive: false)
    ])
) -> some View {
    let store = OrganizationStore(loader: PreviewOrganizations(result: organizations))
    return NavigationStack { HomeView() }
        .environment(AuthSession())
        .environment(UserStore(loader: PreviewLoader(result: user)))
        .environment(store)
        .task { await store.load(forUser: 42, preferring: nil) }
}

#Preview("Several organizations, none chosen") { homePreview() }

#Preview("One organization, chosen automatically") {
    homePreview(organizations: .success([Organization(id: 7, name: "Tornotron Constructions")]))
}

#Preview("No organizations") { homePreview(organizations: .success([])) }

#Preview("Profile failed") {
    homePreview(user: .failure(APIError(message: "Could not reach the server.", status: 0)))
}
