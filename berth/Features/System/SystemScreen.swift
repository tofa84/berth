//
//  SystemScreen.swift
//  berth
//

import SwiftUI
import ContainerAPIClient
import SystemPackage

struct SystemScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.system
        let engine = model.engine
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "System", subtitle: subtitle(engine))

                apiServerCard(store, engine)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    storageCard(store)
                    pathsCard(engine)
                    hostCard()
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { if let e = store.error { ErrorToast(text: e) } }
        .task(id: model.engine.epoch) { await store.load() }
    }

    private func subtitle(_ engine: EngineConnection) -> String {
        if let h = engine.health {
            return "\(h.apiServerAppName) \(engine.version ?? "?") · build \(h.apiServerBuild) · commit \(String(h.apiServerCommit.prefix(7)))"
        }
        return "engine not reachable"
    }

    private func apiServerCard(_ store: SystemStore, _ engine: EngineConnection) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    StatusDot(color: engine.isRunning ? Theme.green : Theme.red, pulse: engine.isRunning, size: 9)
                    Text("API server").font(.berthSans(14, .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(engine.isRunning ? "running" : "stopped")
                        .font(.berthMono(11)).foregroundStyle(engine.isRunning ? Theme.green : Theme.red)
                    Spacer()
                    if store.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        if engine.isRunning {
                            SecondaryButton(title: "Restart", systemImage: "arrow.clockwise") { Task { await store.restart() } }
                            SecondaryButton(title: "Stop", systemImage: "stop.fill", role: .destructive) { Task { await store.stop() } }
                        } else {
                            AccentButton(title: "Start", systemImage: "play.fill") { Task { await store.start() } }
                        }
                    }
                }
                Divider().overlay(Theme.border)
                KeyValue("Mach service", "com.apple.container.apiserver")
                if let h = engine.health {
                    KeyValue("Version", engine.version ?? h.apiServerVersion)
                    KeyValue("Commit", h.apiServerCommit)
                    KeyValue("Install root", h.installRoot.path)
                }
            }
        }
    }

    private func storageCard(_ store: SystemStore) -> some View {
        InfoCard(title: "Storage") {
            KeyValue("Images", Format.bytes(store.imageSize))
            KeyValue("Volumes", Format.bytes(store.volumeSize))
            KeyValue("Reclaimable", Format.bytes(store.reclaimable))
            HStack {
                Spacer()
                SecondaryButton(title: "Prune images") { Task { await store.prune() } }
            }
        }
    }

    private func pathsCard(_ engine: EngineConnection) -> some View {
        InfoCard(title: "Paths") {
            if let h = engine.health {
                KeyValue("App root", h.appRoot.path)
                KeyValue("Install root", h.installRoot.path)
                KeyValue("Log root", h.logRoot?.string ?? "os_log")
            } else {
                Text("Unavailable").font(.berthSans(12)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func hostCard() -> some View {
        let info = ProcessInfo.processInfo
        let gb = Int((Double(info.physicalMemory) / 1_073_741_824).rounded())
        return InfoCard(title: "Host") {
            KeyValue("Hostname", DisplayHost.name)
            KeyValue("CPU cores", "\(info.processorCount)")
            KeyValue("Memory", "\(gb) GB")
            KeyValue("macOS", info.operatingSystemVersionString)
        }
    }
}
