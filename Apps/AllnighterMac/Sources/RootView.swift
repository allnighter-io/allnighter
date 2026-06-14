import SwiftUI
import AppKit
import AllnighterCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            PanelSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                PromptComposer()
                Divider()
                RunResultsView()
            }
        }
    }
}

// MARK: - Panel sidebar

private struct PanelSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Panel") {
                ForEach(model.workers) { worker in
                    WorkerRow(worker: worker)
                }
            }
            Section {
                Button {
                    model.checkHealth()
                } label: {
                    Label("Check worker health", systemImage: "stethoscope")
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct WorkerRow: View {
    @Environment(AppModel.self) private var model
    let worker: Worker

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.toggle(worker)
            } label: {
                Image(systemName: worker.enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(worker.enabled ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(worker.displayName).font(.body)
                Text(model.driverName(for: worker))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            healthBadge
        }
    }

    @ViewBuilder private var healthBadge: some View {
        switch model.health[worker.id] {
        case .healthy:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).help("Healthy")
        case .unhealthy(let reason):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(reason)
        case .unknown:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help("Manual / unknown")
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Prompt composer

private struct PromptComposer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(.headline)
            TextEditor(text: $model.prompt)
                .font(.body)
                .frame(minHeight: 90, maxHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Text("\(model.enabledWorkers.count) workers selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isRunning {
                    Button(role: .destructive) { model.stop() } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                } else {
                    Button { model.runCouncil() } label: {
                        Label("Run council", systemImage: "play.fill")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || model.enabledWorkers.isEmpty)
                }
            }
        }
        .padding()
    }
}

// MARK: - Run results

private struct RunResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let run = model.run {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    StatusStrip(run: run)
                    ForEach(run.members) { member in
                        MemberCard(member: member, worker: worker(for: member.workerId))
                    }
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No council yet",
                systemImage: "person.3.sequence",
                description: Text("Type a prompt and run the council. Every worker answers in parallel.")
            )
        }
    }

    private func worker(for id: String) -> Worker? {
        model.workers.first { $0.id == id }
    }
}

private struct StatusStrip: View {
    let run: CouncilRun

    var body: some View {
        HStack(spacing: 8) {
            ForEach(run.members) { member in
                HStack(spacing: 4) {
                    StatusDot(status: member.status)
                    Text(member.workerId.replacingOccurrences(of: "worker_", with: ""))
                        .font(.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }
            Spacer()
        }
    }
}

private struct StatusDot: View {
    let status: MemberStatus
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
    private var color: Color {
        switch status {
        case .done: return .green
        case .running: return .blue
        case .queued: return .secondary
        case .failed, .timedOut: return .orange
        case .cancelled: return .gray
        case .skipped: return .purple
        }
    }
}

private struct MemberCard: View {
    @Environment(AppModel.self) private var model
    let member: MemberResponse
    let worker: Worker?

    @State private var pasted: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusDot(status: member.status)
                Text(worker?.displayName ?? member.workerId).font(.headline)
                Spacer()
                if let ms = member.durationMs {
                    Text(String(format: "%.1fs", Double(ms) / 1000))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if member.output != nil {
                    Button {
                        copy(member.output ?? "")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy answer")
                }
            }

            switch member.status {
            case .done:
                Text(member.output ?? "")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .running, .queued:
                ProgressView().controlSize(.small)
            case .skipped:
                manualPasteBox
            case .failed, .timedOut:
                Label(member.errorReason ?? member.status.rawValue, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            case .cancelled:
                Text("Cancelled").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var manualPasteBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Manual worker — run this prompt in its app and paste the answer:")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $pasted)
                .frame(minHeight: 60)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Button("Use this answer") {
                model.setManualAnswer(workerId: member.workerId, text: pasted)
            }
            .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
