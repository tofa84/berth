//
//  ContainerDetailView.swift
//  berth
//

import SwiftUI
import ContainerResource
import ContainerizationExtras

struct ContainerDetailView: View {
    @Environment(AppModel.self) private var model
    let containerID: String
    @State private var tab: DetailTab = .overview
    @State private var streams = ContainerStreams()
    @State private var confirmDelete = false

    enum DetailTab: String, CaseIterable {
        case overview = "Overview", logs = "Logs", stats = "Stats", inspect = "Inspect"
    }

    var body: some View {
        let store = model.containers
        if let c = store.snapshot(containerID) {
            VStack(spacing: 0) {
                headerBar(c, store)
                tabBar
                ScrollView { content(c).padding(22) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: "\(containerID)#\(tab.rawValue)") {
                streams.stopAll()
                switch tab {
                case .logs: streams.startLogs(id: containerID, service: model.service)
                case .stats: streams.startStats(id: containerID, service: model.service, cores: c.allocatedCPUs)
                default: break
                }
            }
            .onDisappear { streams.stopAll() }
            .confirmationDialog("Delete container?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await store.delete(c.id) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Forcibly removes the container — a running container is killed first.")
            }
        } else {
            CenteredMessage(systemImage: "questionmark.square.dashed",
                            title: "Container not found",
                            message: "It may have been deleted.",
                            actionTitle: "Back to list") { store.selectedID = nil }
        }
    }

    // MARK: Header

    private func headerBar(_ c: ContainerSnapshot, _ store: ContainersStore) -> some View {
        HStack(spacing: 14) {
            BackButton { store.selectedID = nil }

            StatusDot(color: c.status.color, pulse: c.isRunning, size: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.id).font(.berthSans(17, .semibold)).foregroundStyle(Theme.textPrimary)
                Text("\(c.imageReference) · \(c.shortID)").font(.berthMono(11.5)).foregroundStyle(Theme.textTertiary)
            }
            Text(c.status.label).font(.berthMono(11)).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            if store.busyIDs.contains(c.id) {
                ProgressView().controlSize(.small)
            } else if c.isRunning {
                SecondaryButton(title: "Stop", systemImage: "stop.fill") { Task { await store.stop(c.id) } }
            } else {
                AccentButton(title: "Start", systemImage: "play.fill") { Task { await store.start(c.id) } }
            }
            SecondaryButton(title: "Restart", systemImage: "arrow.clockwise") { Task { await store.restart(c.id) } }
            SecondaryButton(title: "Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    // MARK: Tabs

    private var tabBar: some View {
        DetailTabBar(tabs: DetailTab.allCases, selection: $tab)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ c: ContainerSnapshot) -> some View {
        switch tab {
        case .overview: overview(c)
        case .logs: logsView()
        case .stats: statsView(c)
        case .inspect: inspect(c)
        }
    }

    // MARK: Logs

    private func logsView() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SectionCaption(text: "stdout · stderr")
                Spacer()
                Toggle("Follow", isOn: Binding(get: { streams.follow }, set: { streams.follow = $0 }))
                    .toggleStyle(.switch).tint(Theme.accent)
                    .font(.berthSans(11.5)).foregroundStyle(Theme.textSecondary)
                Text("\(streams.logs.count) lines").font(.berthMono(11)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(streams.logs) { e in
                            logRow(e).id(e.id)
                        }
                        Color.clear.frame(height: 1).id(-1)
                    }
                    .padding(14)
                }
                .onChange(of: streams.logs.count) { _, _ in
                    if streams.follow { proxy.scrollTo(-1, anchor: .bottom) }
                }
            }
            if streams.logs.isEmpty {
                Text("Waiting for output…").font(.berthMono(11.5)).foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .frame(height: 400)
        .codePanel()
    }

    /// One log line: dimmed timestamp, level in a fixed column colored by
    /// severity (amber = warning, red = error), message leading. A subtle bar
    /// on the left marks warnings/errors; unparsed lines render plain.
    @ViewBuilder
    private func logRow(_ e: ContainerStreams.LogEntry) -> some View {
        let p = e.parsed
        Group {
            if p.severity == .sentinel {
                Text(p.message).font(.berthMono(11.5)).italic().foregroundStyle(Theme.textFaint)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    if let timestamp = p.timestamp {
                        Text(timestamp).font(.berthMono(11.5)).foregroundStyle(Theme.textFaint)
                            .frame(minWidth: 88, alignment: .leading)
                    }
                    if let level = p.level {
                        Text(level).font(.berthMono(11.5)).foregroundStyle(levelColor(p.severity))
                            .frame(width: 54, alignment: .leading)
                    }
                    Text(p.message)
                        .font(.berthMono(11.5))
                        .foregroundStyle(p.severity == .error ? Theme.red : Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 6)
                .overlay(alignment: .leading) {
                    if let marker = markerColor(p.severity) {
                        RoundedRectangle(cornerRadius: 1).fill(marker).frame(width: 2)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markerColor(_ severity: LogSeverity) -> Color? {
        switch severity {
        case .warning: Theme.amber
        case .error: Theme.red
        default: nil
        }
    }

    private func levelColor(_ severity: LogSeverity) -> Color {
        switch severity {
        case .warning: Theme.amber
        case .error: Theme.red
        case .info: Theme.textTertiary
        default: Theme.textFaint
        }
    }

    // MARK: Stats

    private func statsView(_ c: ContainerSnapshot) -> some View {
        let s = streams.latest
        return VStack(spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                MetricTile(label: "CPU", value: Format.percent(points: streams.cpuPercentDisplay))
                MetricTile(label: "Memory", value: Format.bytes(s?.memoryUsageBytes),
                           footnote: "limit \(Format.bytes(c.memoryLimitBytes))")
                MetricTile(label: "Net I/O", value: "\(Format.bytes(s?.networkRxBytes)) / \(Format.bytes(s?.networkTxBytes))")
                MetricTile(label: "PIDs", value: s?.numProcesses.map { "\($0)" } ?? "—")
            }
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionCaption(text: "CPU · last 90s")
                        Spacer()
                        Text("peak \(Format.percent(points: (streams.cpuHistory.max() ?? 0) * streams.coresForDisplay * 100))")
                            .font(.berthMono(11)).foregroundStyle(Theme.textTertiary)
                    }
                    BarChart(values: streams.cpuHistory, height: 90, slots: 60)
                }
            }
        }
    }

    private func overview(_ c: ContainerSnapshot) -> some View {
        let attach = c.networks.first
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], spacing: 14) {
            InfoCard(title: "Configuration") {
                KeyValue("Image", c.imageReference)
                KeyValue("Command", c.command)
                KeyValue("Working dir", c.configuration.initProcess.workingDirectory)
                KeyValue("User", "\(c.configuration.initProcess.user)")
                KeyValue("TTY", c.configuration.initProcess.terminal ? "yes" : "no")
                KeyValue("Uptime", c.uptimeText)
            }
            InfoCard(title: "Networking") {
                KeyValue("Network", attach?.network ?? "—")
                KeyValue("IP address", c.primaryIP ?? "—")
                KeyValue("Ports", c.portsSummary)
                KeyValue("Hostname", attach?.hostname ?? "—")
                KeyValue("Gateway", attach.map { String($0.ipv4Gateway.description) } ?? "—")
                KeyValue("MAC", attach?.macAddress.map { "\($0)" } ?? "—")
            }
            InfoCard(title: "Mounts") {
                if c.configuration.mounts.isEmpty {
                    Text("No mounts").font(.berthSans(12)).foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(Array(c.configuration.mounts.enumerated()), id: \.offset) { _, m in
                        HStack(spacing: 8) {
                            Text(shortPath(m.source)).foregroundStyle(Theme.textSecondary)
                            Text("→").foregroundStyle(Theme.textFaint)
                            Text(m.destination).foregroundStyle(Theme.textTertiary).lineLimit(1)
                            Spacer()
                            Text(m.options.readonly ? "ro" : "rw").foregroundStyle(m.options.readonly ? Theme.amber : Theme.greenBright)
                        }
                        .font(.berthMono(11.5))
                    }
                }
            }
            InfoCard(title: "Environment") {
                let env = c.configuration.initProcess.environment
                if env.isEmpty {
                    Text("No variables").font(.berthSans(12)).foregroundStyle(Theme.textTertiary)
                } else {
                    EnvList(items: env)
                }
            }
        }
    }

    private func inspect(_ c: ContainerSnapshot) -> some View {
        InspectPanel(json: Format.prettyJSON(c))
    }

    private func shortPath(_ p: String) -> String {
        (p as NSString).lastPathComponent.isEmpty ? p : (p as NSString).lastPathComponent
    }
}
