//
//  ImagesStoreTests.swift
//  berthTests
//
//  Layer-B store tests: ImagesStore usage counting, list shaping and the
//  prune/pull flows against a scripted FakeContainerService.
//
//  The suite holds `app` as a stored property because the stores keep only an
//  `unowned` back-reference — it must outlive every store call.
//

import Testing
import Foundation
@testable import berth

struct ImagesStoreTests {
    private let nginx = "docker.io/library/nginx:latest"
    private let alpine = "docker.io/library/alpine:latest"

    private let app: AppModel
    private let fake: FakeContainerService
    private let store: ImagesStore

    init() {
        fake = FakeContainerService()
        app = AppModel(service: fake)
        store = app.images
    }

    @Test func usageCountsContainersPerImage() async throws {
        fake.images = [Fixtures.image(name: nginx), Fixtures.image(name: alpine)]
        fake.containers = [
            try Fixtures.snapshot(id: "web1", image: nginx),
            try Fixtures.snapshot(id: "web2", image: nginx),
        ]
        await store.load()
        #expect(store.usedBy(store.image(nginx)!) == 2)
        #expect(store.usedBy(store.image(alpine)!) == 0)
        #expect(store.unusedCount == 1)
        #expect(app.counts[.images] == 2)
    }

    @Test func displayedAppliesSearchUnusedFilterAndSort() async throws {
        fake.images = [
            Fixtures.image(name: nginx, variants: [.init(size: 500)]),
            Fixtures.image(name: alpine, variants: [.init(size: 100)]),
        ]
        fake.containers = [try Fixtures.snapshot(id: "web", image: nginx)]
        await store.load()

        store.sort = .size
        #expect(store.displayed(matching: "").map(\.repository)
            == ["docker.io/library/nginx", "docker.io/library/alpine"])

        #expect(store.displayed(matching: " ALPINE ").map(\.repository) == ["docker.io/library/alpine"])

        store.unusedOnly = true
        #expect(store.displayed(matching: "").map(\.repository) == ["docker.io/library/alpine"])
    }

    @Test func pruneRemovesUnusedSweepsBlobsAndClearsSelection() async throws {
        fake.images = [Fixtures.image(name: nginx), Fixtures.image(name: alpine)]
        fake.containers = [try Fixtures.snapshot(id: "web", image: nginx)]
        await store.load()
        store.selectedID = alpine
        fake.failures["pruneBlobs"] = "sweep failed"
        await store.prune()
        #expect(fake.calls.contains("deleteImage:\(alpine)"))
        #expect(!fake.calls.contains("deleteImage:\(nginx)"))
        #expect(store.actionError == "blobs: sweep failed")
        #expect(store.selectedID == nil)
        #expect(store.all.map(\.repository) == ["docker.io/library/nginx"])
    }

    @Test func deleteClearsMatchingSelection() async throws {
        fake.images = [Fixtures.image(name: alpine)]
        await store.load()
        store.selectedID = alpine
        await store.delete(alpine)
        #expect(store.selectedID == nil)
        #expect(store.all.isEmpty)
    }

    @Test func pullTrimsReferenceAndSkipsBlank() async {
        await store.pull(reference: "   ")
        #expect(fake.calls.isEmpty)

        await store.pull(reference: " alpine ")
        #expect(fake.calls.contains("pull:alpine"))
        // The pull reloads the list on success and ends with no progress shown.
        #expect(fake.callCount("listImages") == 1)
        #expect(store.pullProgress == nil)
    }

    @Test func pullFailureSurfacesError() async {
        fake.failures["pull:alpine"] = "manifest unknown"
        await store.pull(reference: "alpine")
        #expect(store.actionError == "manifest unknown")
        #expect(store.busy == false)
    }
}
