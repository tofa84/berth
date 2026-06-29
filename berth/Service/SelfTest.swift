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

        print("SELFTEST_DONE")
    }
}
#endif
