//
//  BuildsStoreTests.swift
//  berthTests
//
//  Layer-B: BuildsStore against a scripted FakeContainerService. Holds `app`
//  as a stored property (stores keep only an unowned back-reference).
//

import Testing
import Foundation
@testable import berth

struct BuildsStoreTests {
    private let app: AppModel
    private let fake: FakeContainerService
    private let store: BuildsStore

    init() {
        fake = FakeContainerService()
        app = AppModel(service: fake)
        store = app.builds
        // Isolate history writes to a throwaway temp dir.
        store.historyFile = BuildHistoryFile(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    /// Lets the spawned build task run to completion (badge cleared + terminal phase).
    private func settle(timeoutMillis: Int = 2000) async {
        for _ in 0..<(timeoutMillis / 5) {
            if !store.isBuilding && app.counts[.builds] == nil { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func loadMapsBuilderInfo() async {
        fake.builderInfoResult = BuilderInfo(status: .running, imageReference: "img:1", cpus: 2, memoryBytes: 2048)
        await store.load()
        #expect(fake.callCount("builderInfo") == 1)
        guard case .loaded(let info) = store.builder else {
            Issue.record("expected .loaded, got \(store.builder)")
            return
        }
        #expect(info.status == .running)
        #expect(info.imageReference == "img:1")
        #expect(info.cpus == 2)
    }

    @Test func startBuilderFailureSetsActionError() async {
        fake.failures["startBuilder"] = "boom"
        await store.startBuilder()
        #expect(store.actionError == "boom")
        #expect(store.busy == false)
    }

    @Test func startBuildHappyPath() async {
        fake.scriptedBuildEvents = [
            .phase(.building),
            .line("#1 [internal] load build definition from Dockerfile"),
            .line("#1 DONE 0.1s"),
            .phase(.succeeded(tags: ["app:latest"])),
        ]
        let request = BuildRequest(contextDir: "/ctx", dockerfilePath: "/ctx/Dockerfile", tags: ["app:latest"])
        store.startBuild(request)
        #expect(store.isBuilding)
        await settle()

        #expect(store.folder.steps.count == 1)
        #expect(store.rawLines.count == 2)
        guard case .succeeded(let tags) = store.phase else {
            Issue.record("expected .succeeded, got \(String(describing: store.phase))")
            return
        }
        #expect(tags == ["app:latest"])
        #expect(app.counts[.builds] == nil)
        #expect(fake.callCount("performBuild:app:latest") == 1)
        // Success refreshes the Images screen.
        #expect(fake.calls.contains("listImages"))
    }

    @Test func secondBuildWhileBuildingIsIgnored() async {
        fake.delays["performBuild"] = .milliseconds(300)
        fake.scriptedBuildEvents = [.phase(.building), .phase(.succeeded(tags: ["a:1"]))]
        let first = BuildRequest(contextDir: "/ctx", dockerfilePath: "/ctx/Dockerfile", tags: ["a:1"])
        let second = BuildRequest(contextDir: "/ctx", dockerfilePath: "/ctx/Dockerfile", tags: ["b:2"])
        store.startBuild(first)
        store.startBuild(second)  // guarded out — store is already building
        await settle()
        #expect(fake.callCount("performBuild:a:1") == 1)
        #expect(fake.callCount("performBuild:b:2") == 0)
    }

    @Test func scriptedFailureReportsFailedPhase() async {
        fake.failures["performBuild"] = "kaboom"
        let request = BuildRequest(contextDir: "/ctx", dockerfilePath: "/ctx/Dockerfile", tags: ["x:1"])
        store.startBuild(request)
        await settle()
        guard case .failed(let message) = store.phase else {
            Issue.record("expected .failed, got \(String(describing: store.phase))")
            return
        }
        #expect(message == "kaboom")
        #expect(app.counts[.builds] == nil)
        // No image refresh on failure.
        #expect(fake.callCount("listImages") == 0)
    }

    @Test func cancelBuildReportsCancelled() async {
        fake.delays["performBuild"] = .seconds(5)
        let request = BuildRequest(contextDir: "/ctx", dockerfilePath: "/ctx/Dockerfile", tags: ["x:1"])
        store.startBuild(request)
        #expect(store.isBuilding)
        store.cancelBuild()
        #expect(!store.isBuilding)
        guard case .failed(let message) = store.phase else {
            Issue.record("expected .failed, got \(String(describing: store.phase))")
            return
        }
        #expect(message == "Cancelled")
        await settle()
        #expect(app.counts[.builds] == nil)
    }

    @Test func succeededBuildIsRecordedInHistory() async {
        fake.scriptedBuildEvents = [.phase(.building), .phase(.succeeded(tags: ["h:1"]))]
        let request = BuildRequest(contextDir: "/ctx", dockerfilePath: "/ctx/Dockerfile", tags: ["h:1"])
        store.startBuild(request)
        await settle()
        #expect(store.history.count == 1)
        #expect(store.history.first?.primaryTag == "h:1")
        guard case .succeeded(let tags) = store.history.first?.outcome else {
            Issue.record("expected .succeeded outcome")
            return
        }
        #expect(tags == ["h:1"])
    }

    @Test func stopBuilderUpdatesStatus() async {
        fake.builderInfoResult = BuilderInfo(status: .running)
        await store.load()
        await store.stopBuilder()
        #expect(fake.calls.contains("stopBuilder"))
        guard case .loaded(let info) = store.builder else {
            Issue.record("expected .loaded")
            return
        }
        #expect(info.status == .stopped)
    }
}
