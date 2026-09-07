import Foundation
import Testing
@testable import EchnoKit

private func user(id: Int64 = 42, name: String = "Ravi Kumar") -> User {
    User(id: id, name: name, email: "ravi@echno.in", skills: ["Rigging"])
}

/// A loader that can be held mid-flight, so a test can interleave `clear()`
/// with a load that has already started.
private actor BlockingLoader: UserLoading {
    private var resume: CheckedContinuation<Void, Never>?
    private var isWaiting = false

    func currentUser() async throws -> User {
        await withCheckedContinuation { continuation in
            resume = continuation
            isWaiting = true
        }
        return user(name: "Previous User")
    }

    /// Waits until the loader has actually suspended, so the test is not racing
    /// the thing it means to control.
    func waitUntilBlocked() async {
        while !isWaiting { await Task.yield() }
    }

    func release() {
        resume?.resume()
        resume = nil
    }
}

private actor StubLoader: UserLoading {
    private(set) var loads = 0
    var result: Result<User, any Error> = .success(user())

    func currentUser() async throws -> User {
        loads += 1
        return try result.get()
    }

    func setResult(_ newValue: Result<User, any Error>) { result = newValue }
}

@Suite("User store")
@MainActor
struct UserStoreTests {

    @Test("Loading publishes the user and clears the loading flag")
    func loads() async {
        let store = UserStore(loader: StubLoader())
        await store.load()

        #expect(store.currentUser?.name == "Ravi Kumar")
        #expect(!store.isLoading)
        #expect(store.error == nil)
    }

    @Test("A failure is held as state, not thrown at the view")
    func holdsFailure() async {
        // Views own feedback; stores own data. A store that threw would put a
        // do/catch in every view body.
        let loader = StubLoader()
        await loader.setResult(.failure(APIError(message: "Session expired", status: 401)))
        let store = UserStore(loader: loader)

        await store.load()
        #expect(store.currentUser == nil)
        #expect(store.error != nil)
        #expect(!store.isLoading)
    }

    @Test("A second load is skipped while one is already running")
    func doesNotStampede() async {
        // Several views appearing at once must not each fire their own request.
        let loader = StubLoader()
        let store = UserStore(loader: loader)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { await store.load() } }
        }
        #expect(await loader.loads == 1)
    }

    @Test("A full Dto response replaces the cached value outright")
    func fullDtoReplaces() async {
        // Rule 1 of three. PATCH /user/web/{id} answers with a whole UserDto,
        // so replacing is safe and keeps the cache exactly what the server holds.
        let store = UserStore(loader: StubLoader())
        await store.load()
        store.replace(with: user(name: "Ravi K."))

        #expect(store.currentUser?.name == "Ravi K.")
        #expect(store.currentUser?.skills == ["Rigging"])
    }

    @Test("Replacing a different user is refused rather than corrupting the cache")
    func refusesMismatchedReplace() async {
        // The cache holds *the signed-in user*. Writing someone else into it
        // would silently show one person another's profile.
        let store = UserStore(loader: StubLoader())
        await store.load()
        store.replace(with: user(id: 99, name: "Someone Else"))

        #expect(store.currentUser?.id == 42)
        #expect(store.currentUser?.name == "Ravi Kumar")
    }

    @Test("An acknowledgement-only response refetches instead of guessing")
    func acknowledgementRefetches() async {
        // Rule 3 of three. An ack carries no state, so the only correct action
        // is to ask the server again — patching the cache from nothing is how
        // stale data gets displayed as fresh.
        let loader = StubLoader()
        let store = UserStore(loader: loader)
        await store.load()
        #expect(await loader.loads == 1)

        await store.reload()
        #expect(await loader.loads == 2)
    }

    @Test("A load that resumes after clear() cannot restore the signed-out user")
    func clearInvalidatesInFlightLoad() async {
        // Sign-out can land while a load is suspended. Without invalidation the
        // resumed load writes the previous user straight back into the cache,
        // and the next screen shows the person who just signed out.
        let loader = BlockingLoader()
        let store = UserStore(loader: loader)

        let load = Task { await store.load() }
        await loader.waitUntilBlocked()

        store.clear()
        await loader.release()
        await load.value

        #expect(store.currentUser == nil)
        #expect(store.error == nil)
        #expect(!store.isLoading)
    }

    @Test("Signing out clears the cached user")
    func clearsOnSignOut() async {
        // Leaving it would show the previous user's name behind the next
        // sign-in screen.
        let store = UserStore(loader: StubLoader())
        await store.load()
        store.clear()

        #expect(store.currentUser == nil)
        #expect(store.error == nil)
    }
}
