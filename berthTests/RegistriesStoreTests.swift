//
//  RegistriesStoreTests.swift
//  berthTests
//
//  Layer-B store tests: RegistriesStore login/logout result handling and
//  search.
//
//  The suite holds `app` as a stored property because the stores keep only an
//  `unowned` back-reference — it must outlive every store call.
//

import Testing
import Foundation
@testable import berth

struct RegistriesStoreTests {
    private let app: AppModel
    private let fake: FakeContainerService
    private let store: RegistriesStore

    init() {
        fake = FakeContainerService()
        app = AppModel(service: fake)
        store = app.registries
    }

    @Test func loginSuccessReturnsTrueAndReloads() async {
        let ok = await store.login(host: "ghcr.io", username: "octocat", password: "secret")
        #expect(ok)
        #expect(fake.calls.contains("login:ghcr.io"))
        #expect(fake.callCount("listRegistries") == 1)
        #expect(store.actionError == nil)
    }

    @Test func loginFailureReturnsFalseWithError() async {
        fake.failures["login:ghcr.io"] = "denied"
        let ok = await store.login(host: "ghcr.io", username: "octocat", password: "bad")
        #expect(!ok)
        #expect(store.actionError == "denied")
        #expect(store.busy == false)
    }

    @Test func logoutRemovesRegistryOnReload() async {
        fake.registries = [Fixtures.registry(host: "ghcr.io")]
        await store.load()
        #expect(store.all.count == 1)
        await store.logout("ghcr.io")
        #expect(fake.calls.contains("logout:ghcr.io"))
        #expect(store.all.isEmpty)
    }

    @Test func searchMatchesHostOrUsername() async {
        fake.registries = [
            Fixtures.registry(host: "ghcr.io", username: "octocat"),
            Fixtures.registry(host: "docker.io", username: "alice"),
        ]
        await store.load()
        #expect(store.displayed(matching: "GHCR").count == 1)
        #expect(store.displayed(matching: "alice").count == 1)
        #expect(store.displayed(matching: "").count == 2)
    }
}
