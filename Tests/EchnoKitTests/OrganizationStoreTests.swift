import Foundation
import Testing
@testable import EchnoKit

private struct StubLoader: OrganizationLoading {
    var result: Result<[Organization], any Error>
    func organizations(forUser id: Int64) async throws -> [Organization] { try result.get() }
}

private func org(_ id: Int64, _ name: String = "Org") -> Organization {
    Organization(id: id, name: name)
}

@Suite("Organization selection")
struct OrganizationSelectionTests {

    @Test("The user's default organization is chosen when they belong to it")
    func honoursTheDefault() {
        let chosen = Organization.selection(
            from: [org(1), org(7), org(9)],
            preferring: 7
        )
        #expect(chosen?.id == 7)
    }

    @Test("A single membership is chosen without asking")
    func singleMembershipIsAutomatic() {
        // Nobody should be made to pick from a list of one.
        #expect(Organization.selection(from: [org(1)], preferring: nil)?.id == 1)
    }

    @Test("Several memberships and no usable default means nothing is chosen")
    func ambiguityIsNotResolved() {
        // Deliberately nil rather than "first". X-Organization-Id is a tenant
        // boundary; picking one on the user's behalf means they may file
        // against the wrong site without ever having been asked. The UI has to
        // ask, so the store must be able to say it does not know.
        #expect(Organization.selection(from: [org(1), org(2)], preferring: nil) == nil)
    }

    @Test("A default pointing somewhere the user does not belong is not honoured")
    func staleDefaultIsIgnored() {
        // A stale defaultOrganizationId survives being removed from an org.
        // Trusting it would send the header for a tenant the caller has no
        // membership in — a 403 at best, and at worst a confusing empty app.
        #expect(Organization.selection(from: [org(1), org(2)], preferring: 99) == nil)
    }

    @Test("A stale default still resolves when there is only one membership")
    func staleDefaultFallsBackToTheOnlyOne() {
        #expect(Organization.selection(from: [org(5)], preferring: 99)?.id == 5)
    }

    @Test("No memberships means nothing is chosen")
    func emptyChoosesNothing() {
        #expect(Organization.selection(from: [], preferring: 7) == nil)
    }
}

@Suite("Organization store")
@MainActor
struct OrganizationStoreTests {

    @Test("A load fills the list and resolves a selection")
    func loadsAndSelects() async {
        let store = OrganizationStore(loader: StubLoader(result: .success([org(7, "Tornotron")])))
        await store.load(forUser: 42, preferring: nil)
        #expect(store.organizations.count == 1)
        #expect(store.selected?.id == 7)
        #expect(store.error == nil)
    }

    @Test("A failure is held for a view to present, not thrown at it")
    func holdsTheFailure() async {
        let store = OrganizationStore(
            loader: StubLoader(result: .failure(APIError(message: "no", status: 500)))
        )
        await store.load(forUser: 42, preferring: nil)
        #expect(store.error != nil)
        #expect(store.organizations.isEmpty)
        #expect(store.selected == nil)
    }

    @Test("Selecting is restricted to organizations the user belongs to")
    func selectionIsRestricted() async {
        // The tenant boundary again: a store that accepts any id is one bad
        // call site away from sending a header nobody is entitled to.
        let store = OrganizationStore(loader: StubLoader(result: .success([org(1), org(2)])))
        await store.load(forUser: 42, preferring: nil)
        store.select(id: 99)
        #expect(store.selected == nil)
        store.select(id: 2)
        #expect(store.selected?.id == 2)
    }

    @Test("Clearing drops the list and the selection together")
    func clearDropsEverything() async {
        let store = OrganizationStore(loader: StubLoader(result: .success([org(1)])))
        await store.load(forUser: 42, preferring: nil)
        store.clear()
        #expect(store.organizations.isEmpty)
        #expect(store.selected == nil)
    }
}
