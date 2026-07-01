//
//  DashboardScreen.swift
//  berth
//

import SwiftUI
import ContainerResource

struct DashboardScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmCleanUp = false

    var body: some View {
        let store = model.dashboard
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(
                    title: "Overview",
                    subtitle: "\(store.running) of \(store.total) containers running · refreshed \(Format.relative(store.lastRefresh))"
                )

                statCards(store)
                machineLoad(store)
                panels(store)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { if let e = store.actionError { ErrorToast(text: e) } }
        .confirmationDialog("Clean up reclaimable data?",
                            isPresented: $confirmCleanUp, titleVisibility: .visible) {
            Button("Delete unused images", role: .destructive) {
                Task { await store.cleanUp() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently removes every image not used by a container and reclaims orphaned data — frees about \(Format.bytes(store.reclaimable)).")
        }
        .task { store.start() }
        .onDisappear { store.stop() }
    }

    private func statCards(_ s: DashboardStore) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            MetricTile(label: "Running", value: "\(s.running) / \(s.total)", footnote: "containers active")
            MetricTile(label: "Images", value: "\(s.imageCount)", footnote: "\(Format.bytes(s.imageSize)) on disk")
            MetricTile(label: "Volumes", value: "\(s.volumeCount)", footnote: "\(Format.bytes(s.volumeSize)) on disk")
            MetricTile(label: "Reclaimable", value: Format.bytes(s.reclaimable),
                       footnote: "system df",
                       footnoteAction: s.reclaimable == 0 || s.pruning
                           ? nil
                           : ("· Clean up →", { confirmCleanUp = true }))
        }
    }

    private func machineLoad(_ s: DashboardStore) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionCaption(text: "Machine load")
                    Spacer()
                    Text("aggregate of \(s.running) running · \(s.totalCores) cores")
                        .font(.berthMono(11)).foregroundStyle(Theme.textTertiary)
                }
                HStack(spacing: 30) {
                    DonutGauge(fraction: s.cpuFraction, label: "CPU",
                               detail: "\(Format.percent(points: s.cpuPercent, digits: 0)) · \(s.totalCores) cores")
                    DonutGauge(fraction: s.memFraction, label: "Memory",
                               detail: "\(Format.bytes(s.memUsed)) / \(Format.bytes(s.memLimit))",
                               color: Theme.blue)
                    Rectangle().fill(Theme.border).frame(width: 1, height: 88)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("CPU · last 2 min").font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary)
                            Spacer()
                            Text("peak \(Format.percent(points: (s.cpuHistory.max() ?? 0) * Double(s.totalCores) * 100, digits: 0))")
                                .font(.berthMono(11)).foregroundStyle(Theme.textTertiary)
                        }
                        BarChart(values: s.cpuHistory, height: 62, slots: 60)
                    }
                }
            }
        }
    }

    private func panels(_ s: DashboardStore) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Running containers
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        SectionCaption(text: "Running containers")
                        Spacer()
                        Button { model.selection = .containers } label: {
                            Text("View all →").font(.berthSans(11.5, .medium)).foregroundStyle(Theme.accent)
                        }.buttonStyle(.plain)
                    }
                    .padding(.bottom, 4)
                    if s.runningContainers.isEmpty {
                        Text("Nothing running").font(.berthSans(12)).foregroundStyle(Theme.textTertiary)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(s.runningContainers.prefix(5)) { c in
                            HStack(spacing: 12) {
                                StatusDot(color: Theme.green, size: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.id).font(.berthSans(13)).foregroundStyle(Theme.textPrimary)
                                    Text(c.imageReference).font(.berthMono(11)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Format.percent(points: s.perStats[c.id]?.cpu ?? 0)).font(.berthMono(12)).foregroundStyle(Theme.textSecondary)
                                    Text(Format.bytes(s.perStats[c.id]?.mem)).font(.berthMono(10.5)).foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .padding(.vertical, 8)
                            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                            .contentShape(Rectangle())
                            .onTapGesture { model.selection = .containers; model.containers.selectedID = c.id }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Activity (derived from start times)
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    SectionCaption(text: "Activity").padding(.bottom, 4)
                    let recent = s.runningContainers.sorted { ($0.startedDate ?? .distantPast) > ($1.startedDate ?? .distantPast) }.prefix(6)
                    if recent.isEmpty {
                        Text("No recent activity").font(.berthSans(12)).foregroundStyle(Theme.textTertiary).padding(.vertical, 10)
                    } else {
                        ForEach(recent) { c in
                            HStack(alignment: .top, spacing: 10) {
                                StatusDot(color: Theme.green, size: 7).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("started \(c.id)").font(.berthSans(12.5)).foregroundStyle(Theme.textSecondary)
                                    Text(c.imageReference).font(.berthMono(10.5)).foregroundStyle(Theme.textFaint).lineLimit(1)
                                }
                                Spacer()
                                Text(Format.uptime(since: c.startedDate)).font(.berthMono(10.5)).foregroundStyle(Theme.textFaint)
                            }
                            .padding(.vertical, 8)
                            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                        }
                    }
                }
            }
            .frame(width: 320)
        }
    }
}
