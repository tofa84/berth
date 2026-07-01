//
//  NetworksStoreTests.swift
//  berthTests
//
//  Layer-B store tests: NetworksStore attachment counting, search and
//  create-input hygiene.
//
//  The suite holds `app` as a stored property because the stores keep only an
//  `unowned` back-reference — it must outlive every store call.
//

import Testing
import Foundation
@testable import berth

struct NetworksStoreTests {
    private let app: AppModel
    private let fake: FakeContainerService
    private let store: NetworksStore

    init() {
        app = AppModel()
        fake = FakeContainerService()
        store = NetworksStore(service: fake, app: app)
    }

    @Test func usageCountsAttachedContainers() async throws {
        fake.networks = [try Fixtures.network(name: "default")]
        fake.containers = [
            // The snapshot fixture attaches to network "default" when ipv4 is set.
            try Fixtures.snapshot(id: "web", ipv4: "192.168.64.5/24"),
            try Fixtures.snapshot(id: "db", ipv4: nil),
        ]
        await store.load()
        #expect(store.usedBy(store.all[0]) == 1)
        #expect(app.counts[.networks] == 1)
    }

    @Test func searchMatchesNameOrSubnet() async throws {
        fake.networks = [try Fixtures.network(name: "default", subnet: "192.168.64.0/24")]
        await store.load()
        #expect(store.displayed(matching: "192.168").count == 1)
        #expect(store.displayed(matching: "DEFAULT").count == 1)
        #expect(store.displayed(matching: "10.0").isEmpty)
    }

    @Test func createTrimsNameAndSkipsEmpty() async {
        await store.create(name: "   ")
        #expect(fake.calls.isEmpty)

        await store.create(name: " backend ")
        #expect(fake.calls.contains("createNetwork:backend"))
    }

    @Test func deleteFailureSurfacesToast() async throws {
        fake.networks = [try Fixtures.network(name: "default")]
        await store.load()
        fake.failures["deleteNetwork"] = "network busy"
        await store.delete("default")
        #expect(store.actionError == "network busy")
        #expect(store.busy == false)
    }
}
