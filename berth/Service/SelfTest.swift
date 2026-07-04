//
//  SelfTest.swift
//  berth
//
//  DEBUG-only headless verification harness. Run the built binary with
//  BERTH_SELFTEST=1 to exercise the real service/store data paths against a
//  live engine and print the results, then exit. Used for CI-less local
//  verification when a screenshot isn't available. Excluded from release.
//

#if DEBUG
import Foundation
import ContainerResource

@MainActor
enum SelfTest {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BERTH_SELFTEST"] == "1"
    }

    static func run(_ model: AppModel) async {
        await model.engine.refresh()
        print("SELFTEST engine running=\(model.engine.isRunning) version=\(model.engine.version ?? "?")")

        await model.containers.load()
        let containers = model.containers.all
        print("SELFTEST containers=\(containers.count)")
        for c in containers {
            print("  - \(c.id) [\(c.status.label)] \(c.imageReference) ip=\(c.primaryIP ?? "-") ports=\(c.portsSummary) up=\(Format.uptime(since: c.startedDate))")
        }

        if let demo = containers.first(where: { $0.status == .running }) {
            var collected = 0
            let logTask = Task {
                for await line in model.service.logStream(id: demo.id) {
                    print("LOG[\(line.kind)] \(line.text)")
                    collected += 1
                    if collected >= 3 { break }
                }
            }
            try? await Task.sleep(for: .seconds(5))
            logTask.cancel()
            print("SELFTEST logs collected=\(collected)")

            if let s1 = try? await model.service.stats(id: demo.id) {
                try? await Task.sleep(for: .seconds(2))
                let s2 = try? await model.service.stats(id: demo.id)
                print("SELFTEST stats mem=\(s2?.memoryUsageBytes ?? 0) cpuΔ=\((s2?.cpuUsageUsec ?? 0) - (s1.cpuUsageUsec ?? 0)) pids=\(s2?.numProcesses ?? 0)")
            }
        }

        let active = Set(containers.map { $0.imageReference })
        if let img = try? await model.service.imageSummary(active: active) {
            print("SELFTEST images count=\(img.count) size=\(img.totalSize) reclaimable=\(img.reclaimable)")
        } else {
            print("SELFTEST images FAILED")
        }
        if let vol = try? await model.service.volumeSummary() {
            print("SELFTEST volumes count=\(vol.count) size=\(vol.totalSize)")
        } else {
            print("SELFTEST volumes FAILED")
        }

        // Phase 4 list paths
        if let imgs = try? await model.service.listImages() {
            print("SELFTEST listImages=\(imgs.count)\(imgs.first.map { " first=\($0.repository):\($0.tag) arch=\($0.platformsText)" } ?? "")")
        } else { print("SELFTEST listImages FAILED") }
        if let vols = try? await model.service.listVolumes() {
            print("SELFTEST listVolumes=\(vols.count)")
        } else { print("SELFTEST listVolumes FAILED") }
        if let nets = try? await model.service.listNetworks() {
            print("SELFTEST listNetworks=\(nets.count)\(nets.first.map { " first=\($0.name) subnet=\($0.subnetText)" } ?? "")")
        } else { print("SELFTEST listNetworks FAILED") }

        // Phase 5: run path (create a throwaway container, verify, clean up)
        let rf = RunFormModel()
        rf.image = "docker.io/library/alpine:latest"
        rf.name = "berth-run-test"
        rf.env = [.init(key: "FOO", value: "bar")]
        print("SELFTEST runPreview: \(rf.commandPreview)")
        let ok = await rf.run()
        await model.containers.load()
        let exists = model.containers.all.contains { $0.id == "berth-run-test" }
        print("SELFTEST run ok=\(ok) exists=\(exists) err=\(rf.error ?? "-")")
        try? await model.service.deleteContainer(id: "berth-run-test", force: true)

        // Phase 6/7: system disk + registries
        await model.system.load()
        print("SELFTEST system images=\(model.system.imageSize) volumes=\(model.system.volumeSize) reclaimable=\(model.system.reclaimable)")
        if let regs = try? await model.service.listRegistries() {
            print("SELFTEST registries=\(regs.count)")
        } else { print("SELFTEST registries FAILED") }

        // Phase 8: builds (native gRPC path)
        await buildsSection(model)

        print("SELFTEST_DONE")
    }

    /// Exercises the native build path end-to-end: builder status, a real
    /// successful build (verified to land in Images), and a failing build
    /// (verified to report failure). Best-effort cleanup of the test images.
    static func buildsSection(_ model: AppModel) async {
        let info = try? await model.service.builderInfo()
        print("SELFTEST builder status=\(String(describing: info?.status)) image=\(info?.imageReference ?? "-") cpus=\(info?.cpus ?? -1)")

        await runBuild(model, name: "ok", dockerfile: "FROM alpine:latest\nRUN echo berth-selftest-ok\n", tag: "berth-selftest-ok:latest", expectSuccess: true)
        await runBuild(model, name: "fail", dockerfile: "FROM alpine:latest\nRUN false\n", tag: "berth-selftest-fail:latest", expectSuccess: false)

        // Store-driven build — the exact data path the UI uses (BuildsStore folding
        // the real service's event stream into steps, plus a history record).
        await runBuildViaStore(model)

        // Cleanup: drop any images this section built.
        await model.images.load()
        for image in model.images.all where image.name.contains("berth-selftest") {
            try? await model.service.deleteImage(reference: image.name)
        }
    }

    private static func runBuild(_ model: AppModel, name: String, dockerfile: String, tag: String, expectSuccess: Bool) async {
        let fm = FileManager.default
        let ctx = fm.temporaryDirectory.appendingPathComponent("berth-selftest-\(name)-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: ctx) }
        do {
            try fm.createDirectory(at: ctx, withIntermediateDirectories: true)
            try Data(dockerfile.utf8).write(to: ctx.appendingPathComponent("Dockerfile"))
        } catch {
            print("SELFTEST build \(name) setup FAILED: \(error)")
            return
        }
        let request = BuildRequest(contextDir: ctx.path, dockerfilePath: ctx.appendingPathComponent("Dockerfile").path, tags: [tag])
        var stepLines = 0
        var finalPhase: BuildPhase?
        for await event in model.service.performBuild(request) {
            switch event {
            case .line(let line): if line.hasPrefix("#") { stepLines += 1 }
            case .phase(let phase): finalPhase = phase
            case .builderPull: break
            }
        }
        let succeeded: Bool
        if case .succeeded = finalPhase { succeeded = true } else { succeeded = false }
        let verdict = succeeded == expectSuccess ? "OK" : "MISMATCH"
        print("SELFTEST build \(name) [\(verdict)] steps=\(stepLines) succeeded=\(succeeded) expected=\(expectSuccess) final=\(String(describing: finalPhase))")
    }

    private static func runBuildViaStore(_ model: AppModel) async {
        let fm = FileManager.default
        let ctx = fm.temporaryDirectory.appendingPathComponent("berth-selftest-store-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: ctx) }
        do {
            try fm.createDirectory(at: ctx, withIntermediateDirectories: true)
            try Data("FROM alpine:latest\nRUN echo berth-selftest-store\n".utf8)
                .write(to: ctx.appendingPathComponent("Dockerfile"))
        } catch {
            print("SELFTEST build store setup FAILED: \(error)")
            return
        }
        let store = model.builds
        // Keep the user's real build history clean — record into a temp dir.
        store.historyFile = BuildHistoryFile(directory: ctx.appendingPathComponent("history"))
        let historyBefore = store.history.count
        let request = BuildRequest(contextDir: ctx.path, dockerfilePath: ctx.appendingPathComponent("Dockerfile").path, tags: ["berth-selftest-store:latest"])
        store.startBuild(request)
        // Wait for the store to reach a terminal phase (bounded).
        for _ in 0..<600 {
            if let phase = store.phase, phase.isTerminal { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let succeeded: Bool
        if case .succeeded = store.phase { succeeded = true } else { succeeded = false }
        // Give finishBuild a moment to record history + refresh images.
        try? await Task.sleep(for: .milliseconds(300))
        let verdict = succeeded ? "OK" : "MISMATCH"
        print("SELFTEST build store [\(verdict)] steps=\(store.folder.steps.count) succeeded=\(succeeded) historyΔ=\(store.history.count - historyBefore) badge=\(model.counts[.builds] == nil ? "clear" : "set")")
    }
}
#endif
