//
//  BuildActivityView.swift
//  berth
//
//  The running / most-recent build: a phase header (cancel while running, hand
//  off to Images on success), a structured step list parsed from the plain
//  progress, and a raw-log toggle. Step detail expands on tap.
//

import SwiftUI

struct BuildActivityView: View {
    @Environment(AppModel.self) private var model
    let store: BuildsStore
    @State private var expandedSteps: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            phaseHeader
            if let pull = store.builderPull { builderPullBar(pull) }
            if store.showRawLog {
                rawLog
            } else {
                stepList
            }
        }
    }

    // MARK: Phase header

    private var phaseHeader: some View {
        HStack(spacing: 10) {
            StatusDot(color: phaseColor, pulse: store.isBuilding, size: 9)
            Text(phaseText)
                .font(.berthSans(13.5, .medium))
                .foregroundStyle(phaseTextColor)
                .lineLimit(2)
            Spacer()
            Toggle(isOn: Binding(get: { store.showRawLog }, set: { store.showRawLog = $0 })) {
                Text("Raw log").font(.berthSans(11.5))
            }
            .toggleStyle(.button).tint(Theme.accent)
            if store.isBuilding {
                SecondaryButton(title: "Cancel", role: .destructive) { store.cancelBuild() }
            } else if isSucceeded {
                SecondaryButton(title: "Show in Images", systemImage: "square.on.square") {
                    model.selection = .images
                }
            }
        }
    }

    private var isSucceeded: Bool {
        if case .succeeded = store.phase { return true }
        return false
    }

    private var phaseText: String {
        switch store.phase {
        case .preparingBuilder(let message): return message
        case .building: return "Building image…"
        case .importing(let message): return message
        case .succeeded(let tags): return "Built " + tags.joined(separator: ", ")
        case .failed(let message): return Self.cleanMessage(message)
        case nil: return ""
        }
    }

    /// Strips the noisy `unknown: "…"` gRPC wrapper the engine adds to build failures.
    private static func cleanMessage(_ message: String) -> String {
        var m = message
        if m.hasPrefix("unknown: ") { m.removeFirst("unknown: ".count) }
        if m.hasPrefix("\"") && m.hasSuffix("\"") && m.count > 1 {
            m.removeFirst(); m.removeLast()
        }
        return m
    }

    private var phaseColor: Color {
        switch store.phase {
        case .succeeded: return Theme.green
        case .failed: return Theme.red
        default: return Theme.accent
        }
    }

    private var phaseTextColor: Color {
        switch store.phase {
        case .failed: return Theme.red
        default: return Theme.textPrimary
        }
    }

    private func builderPullBar(_ progress: PullProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction).tint(Theme.accent)
                HStack {
                    Text(progress.phase).font(.berthSans(11)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    Spacer()
                    Text("\(Format.bytes(progress.received)) / \(Format.bytes(progress.total))")
                        .font(.berthMono(10.5)).foregroundStyle(Theme.textFaint)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress.phase).font(.berthSans(11)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    // MARK: Step list

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.folder.steps.isEmpty {
                Text("Waiting for build output…")
                    .font(.berthMono(11.5)).foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            } else {
                ForEach(store.folder.steps) { step in
                    stepRow(step)
                    Divider().overlay(Theme.border)
                }
            }
            if !store.folder.trailing.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(store.folder.trailing.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.berthMono(11)).foregroundStyle(Theme.red.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
        }
        .background(Theme.codeBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func stepRow(_ step: BuildStepFolder.Step) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                stepIcon(step.state).frame(width: 16)
                Text(step.title).font(.berthMono(12)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                stepTrailing(step.state)
                if !step.detail.isEmpty {
                    Image(systemName: expandedSteps.contains(step.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9)).foregroundStyle(Theme.textFaint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !step.detail.isEmpty else { return }
                if expandedSteps.contains(step.id) { expandedSteps.remove(step.id) }
                else { expandedSteps.insert(step.id) }
            }
            if expandedSteps.contains(step.id) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(step.detail.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.berthMono(11)).foregroundStyle(Theme.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    @ViewBuilder
    private func stepIcon(_ state: BuildStepFolder.Step.State) -> some View {
        switch state {
        case .running:
            ProgressView().controlSize(.small).scaleEffect(0.7)
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.green)
        case .cached:
            Image(systemName: "checkmark.circle").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
        case .error:
            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.red)
        case .canceled:
            Image(systemName: "minus.circle").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
        }
    }

    @ViewBuilder
    private func stepTrailing(_ state: BuildStepFolder.Step.State) -> some View {
        switch state {
        case .done(let seconds):
            if let seconds {
                Text(String(format: "%.1fs", seconds)).font(.berthMono(11)).foregroundStyle(Theme.textFaint)
            }
        case .cached:
            Text("CACHED").font(.berthSans(10, .semibold)).tracking(0.5).foregroundStyle(Theme.textMuted)
        case .error(let message):
            Text(message).font(.berthMono(11)).foregroundStyle(Theme.red).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 260, alignment: .trailing)
        case .canceled:
            Text("canceled").font(.berthSans(11)).foregroundStyle(Theme.textMuted)
        case .running:
            EmptyView()
        }
    }

    // MARK: Raw log

    private var rawLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(store.rawLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.berthMono(11)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id(-1)
                }
                .padding(12)
            }
            .onChange(of: store.rawLines.count) { _, _ in proxy.scrollTo(-1, anchor: .bottom) }
        }
        .frame(height: 360)
        .background(Theme.codeBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border, lineWidth: 1))
    }
}
