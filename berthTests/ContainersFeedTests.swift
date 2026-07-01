//
//  ContainersFeedTests.swift
//  berthTests
//
//  The shared container-list source: snapshot/badge publication, single-flight
//  dedup of concurrent refreshes, and error propagation.
//
//  The suite holds `app` as a stored property because the feed keeps only an
//  `unowned` back-reference — it must outlive every call.
//

import Testing
import Foundation
@testable import berth

struct ContainersFeedTests {
    private let app: AppModel
    private let fake: FakeContainerService

    init() {
        fake = FakeContainerService()
        app = AppModel(service: fake)
    }

    @Test func refreshPublishesSnapshotsAndBadge() async throws {
        fake.containers = [try Fixtures.snapshot(id: "web")]
        let list = try await app.containersFeed.refresh()
        #expect(list.map(\.shortID) == ["web"])
        #expect(app.containersFeed.snapshots.map(\.shortID) == ["web"])
        #expect(app.counts[.containers] == 1)
    }

    @Test func concurrentRefreshesShareOneFetch() async throws {
        fake.containers = [try Fixtures.snapshot(id: "web")]
        // Hold the fetch open so the second caller arrives while it's in flight.
        fake.delays["listContainers"] = .milliseconds(50)
        let feed = app.containersFeed
        async let first = feed.refresh()
        async let second = feed.refresh()
        _ = try await (first, second)
        #expect(fake.callCount("listContainers") == 1)
    }

    @Test func sequentialRefreshesFetchAgain() async throws {
        _ = try await app.containersFeed.refresh()
        _ = try await app.containersFeed.refresh()
        #expect(fake.callCount("listContainers") == 2)
    }

    @Test func failurePropagatesToCaller() async {
        fake.failures["listContainers"] = "engine offline"
        await #expect(throws: (any Error).self) {
            try await self.app.containersFeed.refresh()
        }
    }
}
