//
//  ContainersStoreTests.swift
//  berthTests
//
//  Layer-B store tests: ContainersStore decision logic against a scripted
//  FakeContainerService (no engine, no XPC). Assertions stick to
//  berth-declared members (shortID, store accessors, fake.calls).
//
//  The suite holds `app` as a stored property because the stores keep only an
//  `unowned` back-reference — it must outlive every store call.
//

import Testing
import Foundation
@testable import berth

struct ContainersStoreTests {
    private let app: AppModel
    private let fake: FakeContainerService
    private let store: ContainersStore

    init() {
        fake = FakeContainerService()
        app = AppModel(service: fake)
        store = app.containers
    }

    @Test func loadSortsByIDAndPublishesCount() async throws {
        fake.containers = [
            try Fixtures.snapshot(id: "web", running: true),
            try Fixtures.snapshot(id: "api", running: false),
        ]
        await store.load()
        #expect(store.all.map(\.shortID) == ["api", "web"])
        #expect(store.runningCount == 1)
        #expect(store.stoppedCount == 1)
        #expect(app.counts[.containers] == 2)
    }

    @Test func loadFailureSurfacesMessage() async {
        fake.failures["listContainers"] = "engine offline"
        await store.load()
        #expect(store.state.errorText == "engine offline")
    }

    @Test func filterNarrowsByStatus() async throws {
        fake.containers = [
            try Fixtures.snapshot(id: "web", running: true),
            try Fixtures.snapshot(id: "api", running: false),
        ]
        await store.load()
        store.filter = .running
        #expect(store.filtered.map(\.shortID) == ["web"])
        store.filter = .stopped
        #expect(store.filtered.map(\.shortID) == ["api"])
    }

    @Test func searchMatchesIDAndImageWithinFilter() async throws {
        fake.containers = [
            try Fixtures.snapshot(id: "web", image: "docker.io/library/nginx:latest", running: true),
            try Fixtures.snapshot(id: "db", image: "docker.io/library/postgres:16", running: false),
        ]
        await store.load()
        // Trimmed + case-insensitive, matching the image reference.
        #expect(store.displayed(matching: "  NGINX ").map(\.shortID) == ["web"])
        // Empty query passes the whole (status-filtered) list through.
        store.filter = .stopped
        #expect(store.displayed(matching: "").map(\.shortID) == ["db"])
        // The search narrows the status filter, not the full list.
        #expect(store.displayed(matching: "nginx").isEmpty)
    }

    @Test func successfulActionReloads() async throws {
        fake.containers = [try Fixtures.snapshot(id: "web", running: false)]
        await store.load()
        await store.start("web")
        #expect(fake.calls.contains("start:web"))
        #expect(fake.callCount("listContainers") == 2)
        #expect(store.actionError == nil)
        #expect(store.busyIDs.isEmpty)
    }

    @Test func actionFailureSetsToastAndSkipsReload() async throws {
        fake.containers = [try Fixtures.snapshot(id: "web", running: true)]
        await store.load()
        fake.failures["stop:web"] = "stop failed"
        await store.stop("web")
        #expect(store.actionError == "stop failed")
        #expect(store.busyIDs.isEmpty)
        #expect(fake.callCount("listContainers") == 1)
    }

    @Test func deleteClearsSelection() async throws {
        fake.containers = [try Fixtures.snapshot(id: "web")]
        await store.load()
        store.selectedID = "web"
        await store.delete("web")
        #expect(fake.calls.contains("deleteContainer:web"))
        #expect(store.selectedID == nil)
        #expect(store.all.isEmpty)
    }

    @Test func pruneDeletesOnlyStoppedAndAggregatesFailures() async throws {
        fake.containers = [
            try Fixtures.snapshot(id: "run1", running: true),
            try Fixtures.snapshot(id: "s1", running: false),
            try Fixtures.snapshot(id: "s2", running: false),
        ]
        await store.load()
        fake.failures["deleteContainer:s1"] = "busy volume"
        await store.pruneStopped()
        #expect(fake.calls.contains("deleteContainer:s2"))
        #expect(!fake.calls.contains("deleteContainer:run1"))
        // A single failure surfaces as its raw message (see pruneSummary).
        #expect(store.actionError == "s1: busy volume")
        // s2 was removed, the failed s1 is still listed after the reload.
        #expect(store.all.map(\.shortID) == ["run1", "s1"])
        #expect(store.busy == false)
    }
}
