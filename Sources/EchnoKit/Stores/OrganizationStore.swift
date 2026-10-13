import Foundation
import Observation

/// What ``OrganizationStore`` needs from a service.
public protocol OrganizationLoading: Sendable {
    func organizations(forUser id: Int64) async throws -> [Organization]
}

extension OrganizationService: OrganizationLoading {}

/// Holds the user's organizations, and which one the app is acting in.
///
/// Follows the shape ``UserStore`` establishes: `@Observable`, `@MainActor`,
/// the store owns data and the view owns feedback, reads de-duplicated.
///
/// The one rule specific to this store is that **selection is restricted to
/// what was loaded**. `X-Organization-Id` is a tenant boundary, and a store
/// that accepted any id would be one bad call site away from sending a header
/// the signed-in user is not entitled to — see `CLAUDE.md` § Security.
@Observable
@MainActor
public final class OrganizationStore {

    /// Everything the user belongs to, once loaded.
    public private(set) var organizations: [Organization] = []

    /// The organization the app is acting in, or `nil` while it is undecided.
    ///
    /// `nil` with a non-empty ``organizations`` is not a bug: it means the user
    /// belongs to several and has not been asked yet.
    public private(set) var selected: Organization?

    public private(set) var isLoading = false

    /// The last failure, for a view to present. Cleared when a load starts.
    public private(set) var error: (any Error)?

    private let loader: any OrganizationLoading

    /// Bumped on ``clear()``, so a load in flight cannot write its result into
    /// the next session — the same race ``UserStore`` guards.
    private var generation = 0

    public init(loader: any OrganizationLoading) {
        self.loader = loader
    }

    /// Loads the memberships if they have not been loaded already.
    ///
    /// - Parameter preferred: `User.defaultOrganizationID`, used to resolve the
    ///   selection — see ``Organization/selection(from:preferring:)``.
    public func load(forUser userID: Int64, preferring preferred: Int64?) async {
        guard !isLoading, organizations.isEmpty else { return }
        await fetch(userID: userID, preferred: preferred)
    }

    /// Loads again regardless of what is cached.
    public func reload(forUser userID: Int64, preferring preferred: Int64?) async {
        await fetch(userID: userID, preferred: preferred)
    }

    private func fetch(userID: Int64, preferred: Int64?) async {
        isLoading = true
        error = nil
        let started = generation
        defer { isLoading = false }

        do {
            let loaded = try await loader.organizations(forUser: userID)
            guard started == generation else { return }
            organizations = loaded
            selected = Organization.selection(from: loaded, preferring: preferred)
        } catch {
            guard started == generation else { return }
            self.error = error
        }
    }

    /// Acts in the organization with this id, if the user belongs to it.
    ///
    /// An id that is not in ``organizations`` is ignored rather than stored.
    /// The alternative is a tenant header for a membership that does not exist.
    public func select(id: Int64) {
        guard let match = organizations.first(where: { $0.id == id }) else { return }
        selected = match
    }

    /// Drops everything, and invalidates any load still in flight.
    ///
    /// Called on sign-out. Without the generation bump, a response that arrived
    /// after the next sign-in would repopulate the previous user's tenants.
    public func clear() {
        generation &+= 1
        organizations = []
        selected = nil
        error = nil
        isLoading = false
    }
}
