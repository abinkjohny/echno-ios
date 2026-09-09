import SwiftUI
import EchnoKit

/// The signed-in landing screen.
///
/// Deliberately thin for now: it identifies who is signed in, which tenant they
/// are acting in, and offers a way out. Attendance summaries and project
/// activity arrive with their modules — putting placeholders here would make the
/// screen look finished when it is not.
struct HomeView: View {

    @Environment(AuthSession.self) private var session
    @Environment(UserStore.self) private var store

    var body: some View {
        List {
            Section {
                switch (store.currentUser, store.error) {
                case (let user?, _):
                    profile(user)
                case (nil, let error?):
                    failure(error)
                case (nil, nil):
                    placeholder
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
        }
        .navigationTitle("Home")
        .refreshable { await store.reload() }
        .task { await store.load() }
    }

    private func profile(_ user: User) -> some View {
        HStack(spacing: 14) {
            EchnoAvatar(initials: user.initials)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name)
                    .font(.headline)
                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let role = user.role {
                    Text(role.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Echno.brand)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Held as state by the store, presented here — the store owns data, the
    /// view owns feedback.
    private func failure(_ error: any Error) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                (error as? LocalizedError)?.errorDescription ?? "Could not load your profile.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.subheadline)
            .foregroundStyle(Echno.destructive)

            Button("Try Again") { Task { await store.reload() } }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    /// Redacted rather than a spinner: the row keeps its shape, so the screen
    /// does not jump when the real name arrives.
    private var placeholder: some View {
        HStack(spacing: 14) {
            EchnoAvatar(initials: "")
            VStack(alignment: .leading, spacing: 3) {
                Text("Loading name").font(.headline)
                Text("loading@example.com").font(.subheadline)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading your profile")
    }
}


// MARK: - Previews
//
// HomeView takes the store from the environment rather than reaching through
// the session, so every state it can be in is reachable here. Without that, the
// loaded state could only be seen by signing in against a live Keycloak.

private struct PreviewLoader: UserLoading {
    var result: Result<User, any Error>
    func currentUser() async throws -> User {
        if case .failure = result { try await Task.sleep(for: .milliseconds(1)) }
        return try result.get()
    }
}

private func previewStore(_ result: Result<User, any Error>) -> UserStore {
    UserStore(loader: PreviewLoader(result: result))
}

private let previewUser = User(
    id: 42,
    name: "Ravi Kumar",
    email: "ravi.kumar@echno.in",
    phone: "+911234567890",
    role: .employee
)

#Preview("Loaded") {
    NavigationStack { HomeView() }
        .environment(AuthSession())
        .environment(previewStore(.success(previewUser)))
}

#Preview("Failed") {
    NavigationStack { HomeView() }
        .environment(AuthSession())
        .environment(previewStore(.failure(APIError(message: "Could not reach the server.", status: 0))))
}
