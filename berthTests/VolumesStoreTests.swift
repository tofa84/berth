//
//  VolumesStoreTests.swift
//  berthTests
//
//  Layer-B store tests: VolumesStore usage counting (distinct containers per
//  volume), prune targeting, and create-input hygiene.
//
//  The suite holds `app` as a stored property because the stores keep only an
//  `unowned` back-reference — it must outlive every store call.
//

import Testing
import Foundation
@testable import berth

struct VolumesStoreTests {
    private let app: AppModel
    private let fake: FakeContainerService
    private let store: VolumesStore

    init() {
        fake = FakeContainerService()
        app = AppModel(service: fake)
        store = app.volumes
    }

    @Test func usageCountsDistinctContainers() async throws {
        fake.volumes = [
            Fixtures.volume(name: "data", source: "/vols/data"),
            Fixtures.volume(name: "logs", source: "/vols/logs"),
        ]
        fake.containers = [
            // Mounting the same named volume at two paths must count as ONE user.
            try Fixtures.snapshot(id: "web", volumeMounts: [("data", "/a"), ("data", "/b")]),
            try Fixtures.snapshot(id: "db", volumeMounts: [("data", "/x")]),
        ]
        await store.load()
        let data = store.all.first { $0.mountPoint == "/vols/data" }!
        let logs = store.all.first { $0.mountPoint == "/vols/logs" }!
        #expect(store.usedBy(data) == 2)
        #expect(store.usedBy(logs) == 0)
    }

    @Test func pruneDeletesOnlyUnusedVolumes() async throws {
        fake.volumes = [
            Fixtures.volume(name: "data", source: "/vols/data"),
            Fixtures.volume(name: "logs", source: "/vols/logs"),
        ]
        fake.containers = [try Fixtures.snapshot(id: "web", volumeMounts: [("data", "/a")])]
        await store.load()
        await store.prune()
        #expect(fake.calls.contains("deleteVolume:logs"))
        #expect(!fake.calls.contains("deleteVolume:data"))
        #expect(store.actionError == nil)
        #expect(store.all.map(\.mountPoint) == ["/vols/data"])
    }

    @Test func createTrimsNameAndSkipsEmpty() async {
        await store.create(name: "   ", size: nil)
        #expect(fake.calls.isEmpty)

        await store.create(name: " cache ", size: nil)
        #expect(fake.calls.contains("createVolume:cache"))
    }

    @Test func deleteFailureSurfacesToast() async throws {
        fake.volumes = [Fixtures.volume(name: "data", source: "/vols/data")]
        await store.load()
        fake.failures["deleteVolume:data"] = "volume in use"
        await store.delete("data")
        #expect(store.actionError == "volume in use")
        #expect(store.busy == false)
    }
}
