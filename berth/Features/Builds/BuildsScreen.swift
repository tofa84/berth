//
//  BuildsScreen.swift
//  berth
//
//  The Builds screen: a builder status/lifecycle card and the running (or most
//  recent) build. Builds are started from the sheet and run over the native
//  gRPC path; the buildkit VM lifecycle is managed here.
//

import SwiftUI

struct BuildsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showSheet = false
    @State private var confirmDeleteBuilder = false

    var body: some View {
        let store = model.builds
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Builds", subtitle: subtitle(store)) {
                AccentButton(title: "Build image…", systemImage: "hammer") { showSheet = true }
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    builderCard(store)
                    if store.phase != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionCaption(text: "Build")
                            BuildActivityView(store: store)
                        }
                    } else if store.history.isEmpty {
                        emptyHint
                    }
                    if !store.history.isEmpty {
                        historySection(store)
                    }
                }
                .padding(22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { if let error = store.actionError { ErrorToast(text: error) } }
        .task(id: model.engine.epoch) { await store.load() }
        .sheet(isPresented: $showSheet) { BuildSheet() }
        .confirmationDialog("Delete builder?", isPresented: $confirmDeleteBuilder, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await store.deleteBuilder() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stops and removes the buildkit container. It is recreated automatically on the next build.")
        }
    }

    private func subtitle(_ store: BuildsStore) -> String {
        store.isBuilding ? "Building…" : "Build images from a Dockerfile with BuildKit."
    }

    private var emptyHint: some View {
        Text("No builds yet. Click “Build image…” to build from a Dockerfile.")
            .font(.berthSans(12.5)).foregroundStyle(Theme.textTertiary)
            .padding(.top, 4)
    }

    // MARK: History

    private func historySection(_ store: BuildsStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(text: "History")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(store.history) { record in
                        historyRow(record)
                        if record.id != store.history.last?.id {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ record: BuildRecord) -> some View {
        HStack(spacing: 12) {
            outcomeIcon(record.outcome)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.primaryTag).font(.berthMono(12.5)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(Format.relative(record.date)) · \(String(format: "%.1fs", record.duration))")
                    .font(.berthSans(11)).foregroundStyle(Theme.textFaint)
            }
            Spacer()
            Button {
                model.buildPrefill = record.request
                showSheet = true
            } label: {
                Text("Re-run").font(.berthSans(11.5, .medium)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private func outcomeIcon(_ outcome: BuildRecord.Outcome) -> some View {
        switch outcome {
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Theme.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(Theme.red)
        case .cancelled:
            Image(systemName: "minus.circle").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
        }
    }

    // MARK: Builder card

    private func builderCard(_ store: BuildsStore) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionCaption(text: "Builder")
                    Spacer()
                    builderStatusBadge(store.builder)
                }
                switch store.builder {
                case .idle, .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking builder…").font(.berthSans(12)).foregroundStyle(Theme.textTertiary)
                    }
                case .failed(let message):
                    Text(message).font(.berthSans(12)).foregroundStyle(Theme.red)
                case .loaded(let info):
                    VStack(alignment: .leading, spacing: 8) {
                        if let image = info.imageReference {
                            KeyValue("Image", image)
                        }
                        if let cpus = info.cpus {
                            KeyValue("CPUs", "\(cpus)")
                        }
                        if let memory = info.memoryBytes {
                            KeyValue("Memory", Format.bytes(memory))
                        }
                    }
                    builderActions(store, info)
                }
            }
        }
    }

    private func builderActions(_ store: BuildsStore, _ info: BuilderInfo) -> some View {
        HStack(spacing: 10) {
            if info.status != .running && info.status != .stopping {
                SecondaryButton(title: store.busy ? "Working…" : "Start builder", systemImage: "play") {
                    Task { await store.startBuilder() }
                }
                .disabled(store.busy)
            }
            if info.status == .running {
                SecondaryButton(title: "Stop", systemImage: "stop") {
                    Task { await store.stopBuilder() }
                }
                .disabled(store.busy)
            }
            if info.status != .notCreated {
                SecondaryButton(title: "Delete", systemImage: "trash", role: .destructive) {
                    confirmDeleteBuilder = true
                }
                .disabled(store.busy)
            }
            if store.busy { ProgressView().controlSize(.small) }
        }
        .padding(.top, 2)
    }

    private func builderStatusBadge(_ state: LoadState<BuilderInfo>) -> some View {
        let (color, text) = statusStyle(state)
        return HStack(spacing: 6) {
            StatusDot(color: color, pulse: text == "running")
            Text(text).font(.berthSans(12)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func statusStyle(_ state: LoadState<BuilderInfo>) -> (Color, String) {
        switch state {
        case .idle, .loading: return (Theme.textFaint, "…")
        case .failed: return (Theme.red, "error")
        case .loaded(let info):
            switch info.status {
            case .running: return (Theme.green, "running")
            case .stopped: return (Theme.textMuted, "stopped")
            case .notCreated: return (Theme.textFaint, "not created")
            case .stopping: return (Theme.amber, "stopping")
            case .unknown: return (Theme.amber, "unknown")
            }
        }
    }
}
