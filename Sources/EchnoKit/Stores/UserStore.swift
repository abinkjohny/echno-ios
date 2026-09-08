import Foundation
import Observation

/// What ``UserStore`` needs from a service.
///
/// A protocol so the store's caching rules can be tested without a network, and
/// so the store depends on a capability rather than a concrete actor.
public protocol UserLoading: Sendable {
    func currentUser() async throws -> User
}

extension UserService: UserLoading {}

/// Holds the signed-in user for the UI.
///
/// ## The convention this file establishes
///
/// - **`@Observable final class`, `@MainActor`.** Views read it directly; the
///   main-actor annotation is what makes that safe under Swift 6 without
///   scattering `await` through view bodies.
/// - **The store owns data; the view owns feedback.** Failures are held in
///   ``error`` for a view to present. No alerts, toasts or haptics here — a
///   store that presented anything could not be reused by a second screen.
/// - **Reads are de-duplicated.** Several views appearing at once must not each
///   fire the same request.
///
/// ## The three mutation-response shapes
///
/// The backend answers mutations in three different shapes and the safe cache
/// action differs per shape. Getting this wrong caused user-visible data loss on
/// web twice, which is why it is written down rather than left to judgement:
///
/// | Response | Action | Here |
/// |---|---|---|
/// | Full `<Domain>Dto` | replace the cached value | ``replace(with:)`` |
/// | `<Domain>SimpleDto` | merge, preserving nested collections | `NestedMergeable` |
/// | Acknowledgement only | refetch — it carries no state | ``reload()`` |
///
/// Name the DTO in a comment above every mutation handler, so the next reader
/// can check the rule was applied rather than inferring it.
@Observable
@MainActor
public final class UserStore {

    /// The signed-in user, once loaded.
    public private(set) var currentUser: User?

    /// True while a load is in flight.
    public private(set) var isLoading = false

    /// The last failure, for a view to present. Cleared when a load starts.
    public private(set) var error: (any Error)?

    private let loader: any UserLoading

    /// Bumped whenever the cache is invalidated, so a load that started before
    /// the change cannot write its result afterwards.
    private var generation = 0

    public init(loader: any UserLoading) {
        self.loader = loader
    }

    /// Loads the user if it has not been loaded already.
    ///
    /// Safe to call from every view's `.task` — a second call while one is in
    /// flight, or after a successful load, does nothing.
    public func load() async {
        guard !isLoading, currentUser == nil else { return }
        await fetch()
    }

    /// Loads again regardless of what is cached.
    ///
    /// This is the correct response to an acknowledgement-only mutation: the
    /// response carries no state, so the only honest thing is to ask again.
    /// Patching the cache from nothing is how stale data ends up displayed as
    /// fresh.
    public func reload() async {
        guard !isLoading else { return }
        await fetch()
    }

    /// Replaces the cached user after a mutation that answered with a full DTO.
    ///
    /// `PATCH /api/v1/user/web/{id}` → `UserDto`, so the response is the whole
    /// record and replacing is safe.
    ///
    /// - Parameter user: The user as the backend now holds it.
    public func replace(with user: User) {
        // The cache holds *the signed-in user*. A different id means the caller
        // mapped the wrong response; writing it would show one person another's
        // profile, which is worse than dropping the update.
        guard currentUser == nil || currentUser?.id == user.id else {
            Log.store.error("Refused to replace user \(String(describing: self.currentUser?.id)) with \(user.id)")
            return
        }
        // A full Dto is the freshest state there is. A read that started before
        // it must not land on top, or the save the user just made reverts on
        // screen a moment later.
        invalidateLoadInFlight()
        currentUser = user
        error = nil
    }

    /// Drops the cached user. Call on sign-out, or the next sign-in screen
    /// shows the previous person's name behind it.
    public func clear() {
        invalidateLoadInFlight()
        currentUser = nil
        error = nil
    }

    /// Discards any load already running, so its result cannot land afterwards.
    ///
    /// Every path that writes ``currentUser`` from outside ``fetch()`` must call
    /// this first. A read that started earlier is, by definition, describing an
    /// older state; letting it commit after a sign-out restores the signed-out
    /// user, and after a mutation it reverts the change the user just made.
    private func invalidateLoadInFlight() {
        generation &+= 1
        isLoading = false
    }

    private func fetch() async {
        let generation = self.generation
        isLoading = true
        error = nil

        let result: Result<User, any Error>
        do {
            result = .success(try await loader.currentUser())
        } catch {
            result = .failure(error)
        }

        // Everything below re-reads state that may have changed while the load
        // was suspended. If it was superseded, this result describes a session
        // that no longer exists — dropping it is the only safe action, and that
        // includes the loading flag, which now belongs to whatever came after.
        guard generation == self.generation else { return }

        switch result {
        case .success(let user): currentUser = user
        case .failure(let error): self.error = error
        }
        isLoading = false
    }
}
