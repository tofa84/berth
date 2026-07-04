//
//  ContainersScreen.swift
//  berth
//

import SwiftUI
import ContainerResource

struct ContainersScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmPrune = false
    @State private var pendingDelete: String?

    var body: some View {
        let store = model.containers
        Group {
            if let id = store.selectedID {
                ContainerDetailView(containerID: id)
            } else {
                list(store)
            }
        }
        .task(id: model.engine.epoch) { await store.load() }
    }

    // Column widths (match the design's grid).
    private let cols = (status: 96.0, id: 96.0, cpu: 60.0, mem: 84.0,
                        ports: 120.0, uptime: 104.0, actions: 84.0, chevron: 22.0)

    @ViewBuilder
    private func list(_ store: ContainersStore) -> some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Containers", subtitle: store.subtitle) {
                HStack(spacing: 10) {
                    SegmentedPills(
                        options: ContainersStore.Filter.allCases.map { ($0, label($0, store)) },
                        selection: $store.filter
                    )
                    SecondaryButton(title: "Prune stopped") { confirmPrune = true }
                        .disabled(store.stoppedCount == 0 || store.busy)
                }
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)

            header
            Divider().overlay(Theme.border)

            switch store.state {
            case .loading, .idle:
                LoadingPlaceholder()
            case .failed(let msg):
                CenteredMessage(systemImage: "exclamationmark.triangle", title: "Couldn’t load containers", message: msg)
            case .loaded:
                if store.filtered.isEmpty {
                    CenteredMessage(systemImage: "rectangle.stack", title: "No containers", message: emptyMessage(store))
                } else {
                    let shown = store.displayed(matching: model.search)
                    if shown.isEmpty {
                        CenteredMessage(systemImage: "magnifyingglass", title: "No matching containers",
                                        message: "No container matches the current search.")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(shown) { c in
                                    row(c, store)
                                    Divider().overlay(Theme.border)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if let err = store.actionError {
                ErrorToast(text: err)
            }
        }
        .confirmationDialog("Prune stopped containers?",
                            isPresented: $confirmPrune, titleVisibility: .visible) {
            Button("Delete \(store.stoppedCount) stopped", role: .destructive) {
                Task { await store.pruneStopped() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently removes all stopped containers. Running containers are not affected.")
        }
        .deleteConfirmation(
            item: $pendingDelete,
            title: "Delete container?",
            message: "Forcibly removes the container — a running container is killed first."
        ) { id in
            Task { await store.delete(id) }
        }
    }

    private func label(_ f: ContainersStore.Filter, _ store: ContainersStore) -> String {
        switch f {
        case .all: "All \(store.totalCount)"
        case .running: "Running \(store.runningCount)"
        case .stopped: "Stopped \(store.stoppedCount)"
        }
    }

    private func emptyMessage(_ store: ContainersStore) -> String {
        switch store.filter {
        case .all: "Run a container to get started."
        case .running: "No running containers."
        case .stopped: "No stopped containers."
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HeaderCell("STATUS", width: cols.status)
            HeaderCell("NAME / IMAGE", width: nil)
            HeaderCell("ID", width: cols.id)
            HeaderCell("CPU", width: cols.cpu, alignment: .trailing)
            HeaderCell("MEM", width: cols.mem, alignment: .trailing)
            HeaderCell("PORTS", width: cols.ports)
            HeaderCell("UPTIME", width: cols.uptime, alignment: .trailing)
            HeaderCell("ACTIONS", width: cols.actions)
            Spacer().frame(width: cols.chevron)
        }
        .padding(.horizontal, 22).padding(.bottom, 8)
    }

    @ViewBuilder
    private func row(_ c: ContainerSnapshot, _ store: ContainersStore) -> some View {
        let busy = store.busyIDs.contains(c.id)
        HStack(spacing: 0) {
            // Status
            HStack(spacing: 7) {
                StatusDot(color: c.status.color, size: 8)
                Text(c.status.label).font(.berthSans(11.5)).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: cols.status, alignment: .leading)

            // Name / image
            VStack(alignment: .leading, spacing: 2) {
                Text(c.id).font(.berthSans(13.5, .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(c.imageReference).font(.berthMono(11)).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 10)

            MonoCell(c.shortID, width: cols.id)
            MonoCell("\(c.allocatedCPUs)×", width: cols.cpu, alignment: .trailing)
            MonoCell(Format.bytes(c.memoryLimitBytes), width: cols.mem, alignment: .trailing)
            MonoCell(c.portsSummary, width: cols.ports)
            MonoCell(c.uptimeText, width: cols.uptime, alignment: .trailing)

            // Actions
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small).frame(width: 28, height: 28)
                } else if c.isRunning {
                    RowIconButton(systemImage: "stop.fill") { Task { await store.stop(c.id) } }
                } else {
                    RowIconButton(systemImage: "play.fill", tint: Theme.greenBright) { Task { await store.start(c.id) } }
                }
                Menu {
                    if c.isRunning {
                        Button("Restart") { Task { await store.restart(c.id) } }
                        Button("Kill") { Task { await store.kill(c.id) } }
                        Divider()
                    }
                    Button("Delete", role: .destructive) { pendingDelete = c.id }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .frame(width: cols.actions, alignment: .leading)

            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                .frame(width: cols.chevron)
        }
        .padding(.horizontal, 22)
        .frame(height: 58)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedID = c.id }
    }
}
