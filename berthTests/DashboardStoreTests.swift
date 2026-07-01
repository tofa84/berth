//
//  DashboardStoreTests.swift
//  berthTests
//
//  Layer-B store tests: the dashboard's aggregate refresh — counts, memory
//  sums, per-container stats (fetched via the concurrent task group) and the
//  resource summaries. CPU percentages need real elapsed wall time, so the
//  delta math is covered separately in CPUSamplerTests.
//
//  The suite holds `app` as a stored property because the stores keep only an
//  `unowned` back-reference — it must outlive every store call.
//

import Testing
import Foundation
@testable import berth

struct DashboardStoreTests {
    private let app: AppModel
    private let fake: FakeContainerService
    private let store: DashboardStore

    init() {
        fake = FakeContainerService()
        app = AppModel(service: fake)
        store = app.dashboard
    }

    @Test func refreshAggregatesRunningContainers() async throws {
        fake.containers = [
            try Fixtures.snapshot(id: "web", cpus: 2, memBytes: 1 << 30, running: true),
            try Fixtures.snapshot(id: "db", cpus: 4, memBytes: 2 << 30, running: true),
            try Fixtures.snapshot(id: "old", running: false),
        ]
        fake.statsByID = [
            "web": Fixtures.stats(id: "web", memoryUsage: 100),
            "db": Fixtures.stats(id: "db", memoryUsage: 200),
        ]
        await store.refreshContainers()
        #expect(store.total == 3)
        #expect(store.running == 2)
        #expect(store.totalCores == 6)
        #expect(store.memUsed == 300)
        #expect(store.memLimit == UInt64(1 << 30) + UInt64(2 << 30))
        #expect(store.perStats["web"]?.mem == 100)
        #expect(store.perStats["db"]?.mem == 200)
        // Stats are fetched once per running container, never for stopped ones.
        #expect(fake.callCount("stats:web") == 1)
        #expect(fake.callCount("stats:db") == 1)
        #expect(fake.callCount("stats:old") == 0)
        #expect(store.cpuHistory.count == 1)
        #expect(store.loaded)
        // The badge comes from the shared feed.
        #expect(app.counts[.containers] == 3)
    }

    @Test func statsFailureKeepsLimitsFromSnapshots() async throws {
        // Memory limit is static config: it must sum from the snapshots even
        // when the stats call fails (nothing scripted → the fake throws).
        fake.containers = [try Fixtures.snapshot(id: "web", memBytes: 1 << 30, running: true)]
        await store.refreshContainers()
        #expect(store.memLimit == 1 << 30)
        #expect(store.memUsed == 0)
        #expect(store.perStats.isEmpty)
        #expect(store.loaded)
    }

    @Test func cleanUpPrunesUnusedImages() async throws {
        // One image in use by a container, one unused: clean-up must delete
        // only the unused one, sweep blobs once, then refresh the summaries.
        fake.containers = [try Fixtures.snapshot(id: "web", image: "docker.io/library/used:latest")]
        fake.images = [
            Fixtures.image(name: "docker.io/library/used:latest"),
            Fixtures.image(name: "docker.io/library/old:latest"),
        ]
        fake.imageSummaryResult = ImageSummary(count: 1, totalSize: 100, reclaimable: 0)
        await store.cleanUp()
        #expect(fake.callCount("deleteImage:docker.io/library/old:latest") == 1)
        #expect(fake.callCount("deleteImage:docker.io/library/used:latest") == 0)
        #expect(fake.callCount("pruneBlobs") == 1)
        #expect(store.actionError == nil)
        // The tile data was refetched after the prune.
        #expect(store.reclaimable == 0)
        #expect(store.imageCount == 1)
        #expect(!store.pruning)
    }

    @Test func cleanUpSurfacesFailure() async throws {
        fake.images = [Fixtures.image(name: "docker.io/library/old:latest")]
        fake.failures["deleteImage:docker.io/library/old:latest"] = "digest in use"
        await store.cleanUp()
        #expect(store.actionError?.contains("digest in use") == true)
        #expect(!store.pruning)
    }

    @Test func refreshResourcesPublishesSummaries() async {
        fake.imageSummaryResult = ImageSummary(count: 3, totalSize: 1_000, reclaimable: 400)
        fake.volumeSummaryResult = VolumeSummary(count: 2, totalSize: 500)
        await store.refreshResources()
        #expect(store.imageCount == 3)
        #expect(store.imageSize == 1_000)
        #expect(store.reclaimable == 400)
        #expect(store.volumeCount == 2)
        #expect(store.volumeSize == 500)
        #expect(app.counts[.images] == 3)
        #expect(app.counts[.volumes] == 2)
    }
}
