import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var showDoctor = false

    var body: some View {
        NavigationSplitView {
            PanelSidebar(showDoctor: $showDoctor)
                .navigationSplitViewColumnWidth(min: 260, ideal: 280)
        } detail: {
            DetailPane()
        }
        .sheet(isPresented: $showDoctor) { DoctorView() }
        .onAppear { GlobalHotKey.enable() }
        .onReceive(NotificationCenter.default.publisher(for: .allnighterQuickCapture)) { _ in
            // Quick capture (P05-S05): bring the composer forward and, when empty,
            // seed the prompt from the clipboard.
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            model.quickCapture(prefillClipboard: true)
        }
    }
}

// MARK: - Detail pane

private struct DetailPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let history = model.historySelection {
            HistoryDetailView(run: history)
        } else {
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
    @Binding var showDoctor: Bool

    var body: some View {
        List {
            Section {
                PresetMenu()
            }
            Section("Panel") {
                ForEach(model.workers) { worker in
                    WorkerRow(worker: worker)
                }
            }
            Section {
                Button {
                    model.runDoctor()
                    showDoctor = true
                } label: {
                    Label(model.isDoctorRunning ? "Running Doctor…" : "Doctor", systemImage: "stethoscope")
                }
                .disabled(model.isDoctorRunning)
            }
            HistorySection()
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Preset menu (P05-S02 / S03)

private struct PresetMenu: View {
    @Environment(AppModel.self) private var model
    @State private var showSavePreset = false
    @State private var presetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(model.panelPresets) { preset in
                    Button {
                        model.applyPreset(preset)
                    } label: {
                        if model.activePresetId == preset.id {
                            Label(preset.displayName, systemImage: "checkmark")
                        } else {
                            Text(preset.displayName)
                        }
                    }
                }
                Divider()
                Button("Save current panel as preset…") { showSavePreset = true }
                if let active = model.panelPresets.first(where: { $0.id == model.activePresetId }), !active.builtIn {
                    Button("Delete “\(active.displayName)”", role: .destructive) { model.deletePreset(active) }
                }
            } label: {
                Label(activeLabel, systemImage: "rectangle.3.group")
            }
            Text("\(model.enabledWorkers.count) workers · synth: \(synthName)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("Save panel preset", isPresented: $showSavePreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") { model.saveCurrentAsPreset(named: presetName); presetName = "" }
            Button("Cancel", role: .cancel) { presetName = "" }
        } message: {
            Text("Saves the enabled workers, the draft synthesizer, and the synthesis instructions.")
        }
    }

    private var activeLabel: String {
        model.panelPresets.first { $0.id == model.activePresetId }?.displayName ?? "Custom panel"
    }

    private var synthName: String {
        model.synthesizerWorker?.displayName ?? "none"
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
                HStack(spacing: 4) {
                    Text(worker.displayName).font(.body)
                    if model.synthesizerWorker?.id == worker.id {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption2).foregroundStyle(.secondary)
                            .help("Draft synthesizer")
                    }
                }
                Text(model.driverName(for: worker))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            healthBadge
        }
    }

    @ViewBuilder private var healthBadge: some View {
        if let d = model.diagnosis(for: worker.id) {
            switch d.health {
            case .healthy:
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    .help(d.version ?? "Healthy")
            case .unhealthy(let reason):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help(d.fixHint ?? reason)
            case .unknown:
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                    .help("Manual / unknown")
            }
        }
    }
}

// MARK: - History (P05-S01)

private struct HistorySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("History") {
            if model.history.isEmpty {
                Text("No runs yet").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.history) { run in
                    Button { model.openHistory(run) } label: {
                        HistoryRow(run: run, selected: model.historySelection?.id == run.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let run: CouncilRun
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(run.prompt)
                .font(.callout).lineLimit(1)
            HStack(spacing: 6) {
                Text(run.createdAt, format: .dateTime.month().day().hour().minute())
                Text("·")
                Text(run.status.rawValue)
                    .foregroundStyle(statusColor)
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
    }

    private var statusColor: Color {
        switch run.status {
        case .complete: return .green
        case .partial, .failed: return .orange
        default: return .secondary
        }
    }
}

private struct HistoryDetailView: View {
    @Environment(AppModel.self) private var model
    let run: CouncilRun

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Past run").font(.caption).foregroundStyle(.secondary)
                        Text(run.createdAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.headline)
                    }
                    Spacer()
                    Button { model.runAgain(run) } label: {
                        Label("Run again", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRunning)
                    Button { model.closeHistory() } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
                GroupBox("Prompt") {
                    Text(run.prompt).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let plan = run.synthesis?.masterPlanMarkdown, !plan.isEmpty {
                    GroupBox("Master Plan") {
                        Text(plan).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { copy(RunMarkdown.bundle(run, workers: model.workers)) } label: {
                        Label("Copy full bundle", systemImage: "tray.and.arrow.up")
                    }
                }
                DisclosureGroup("Member answers (\(run.members.count))") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(run.members) { member in
                            MemberCard(member: member, worker: model.workers.first { $0.id == member.workerId })
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.headline)
            }
            .padding()
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Prompt composer

private struct PromptComposer: View {
    @Environment(AppModel.self) private var model
    @State private var showInstructions = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Prompt").font(.headline)
                Spacer()
                InstructionPicker(showEditor: $showInstructions)
            }
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
        .sheet(isPresented: $showInstructions) { InstructionEditor() }
    }
}

private struct InstructionPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var showEditor: Bool

    var body: some View {
        Menu {
            ForEach(model.instructionPresets) { preset in
                Button {
                    model.selectInstructionPreset(id: preset.id)
                } label: {
                    if model.selectedInstructionPresetId == preset.id && !isCustom {
                        Label(preset.displayName, systemImage: "checkmark")
                    } else {
                        Text(preset.displayName)
                    }
                }
            }
            Divider()
            Button("Edit instructions…") { showEditor = true }
        } label: {
            Label(label, systemImage: "text.append")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var isCustom: Bool {
        model.selectedInstructionPreset?.template != model.instructionText
    }

    private var label: String {
        if isCustom { return "Synthesis: Custom" }
        return "Synthesis: \(model.selectedInstructionPreset?.displayName ?? "default")"
    }
}

private struct InstructionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showSave = false
    @State private var name = ""

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Text("Synthesis instructions").font(.title3.bold())
            Text("The instruction the synthesizer follows to write the master plan. Edits become a custom instruction recorded honestly on the run; save them as a reusable preset.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $model.instructionText)
                .font(.body.monospaced())
                .frame(minWidth: 460, minHeight: 280)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Button("Save as preset…") { showSave = true }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .alert("Save instruction preset", isPresented: $showSave) {
            TextField("Preset name", text: $name)
            Button("Save") { model.saveInstructionPreset(named: name); name = "" }
            Button("Cancel", role: .cancel) { name = "" }
        }
    }
}

// MARK: - Doctor (P05-S04)

private struct DoctorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Doctor", systemImage: "stethoscope").font(.title2.bold())
                Spacer()
                Button {
                    model.runDoctor()
                } label: {
                    Label(model.isDoctorRunning ? "Checking…" : "Re-run", systemImage: "arrow.clockwise")
                }
                .disabled(model.isDoctorRunning)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Detects each worker's CLI, checks the version, and runs a smoke test. A broken or updated CLI fails loudly here with a fix — it never silently drops from the panel.")
                .font(.caption).foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.workers) { worker in
                        DoctorRow(worker: worker, diagnosis: model.diagnosis(for: worker.id))
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct DoctorRow: View {
    let worker: Worker
    let diagnosis: WorkerDiagnosis?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(worker.displayName).font(.headline)
                    Text(diagnosis?.driverName ?? worker.driverId)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let version = diagnosis?.version {
                    Text(version).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if let hint = diagnosis?.fixHint {
                HStack(alignment: .top, spacing: 6) {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(hint, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy fix hint")
                }
            }
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var icon: some View {
        switch diagnosis?.health {
        case .healthy:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        case .unhealthy:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unknown:
            Image(systemName: "hand.raised").foregroundStyle(.secondary)
        case .none:
            ProgressView().controlSize(.small)
        }
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
                    MasterPlanCard(run: run)
                    DisclosureGroup("Member answers (\(run.members.count))") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(run.members) { member in
                                MemberCard(member: member, worker: worker(for: member.workerId))
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.headline)
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

private struct MasterPlanCard: View {
    @Environment(AppModel.self) private var model
    let run: CouncilRun
    @State private var pastedPlan: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Master Plan", systemImage: "doc.text.magnifyingglass").font(.title3.bold())
                Spacer()
                if run.synthesis?.status == .complete {
                    Button { copy(RunMarkdown.masterPlan(run)) } label: {
                        Label("Copy plan", systemImage: "doc.on.doc")
                    }
                    Button { copy(model.bundleMarkdown()) } label: {
                        Label("Copy full bundle", systemImage: "tray.and.arrow.up")
                    }
                }
            }
            content
            if let dir = model.lastSavedDirectory, run.synthesis?.status == .complete {
                Text("Saved to \(dir.path)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.25)))
    }

    @ViewBuilder private var content: some View {
        if run.synthesis?.status == .complete {
            Text(RunMarkdown.masterPlan(run)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if run.status == .synthesizing {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Synthesizing the master plan…") }
        } else if let manual = model.manualSynthesisPrompt {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your synthesizer is a manual worker. Run this prompt in its app, then paste the master plan:")
                    .font(.callout).foregroundStyle(.secondary)
                Button { copy(manual) } label: { Label("Copy synthesis prompt", systemImage: "doc.on.doc") }
                TextEditor(text: $pastedPlan)
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Button("Use this master plan") { model.setManualSynthesis(pastedPlan) }
                    .disabled(pastedPlan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else if run.synthesis?.status == .failed || run.status == .partial {
            Label("Synthesis did not produce a plan. The member answers below are still available.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        } else if run.status == .answersIn {
            Text("No synthesizer is enabled. Enable a worker that can synthesize (e.g. Opus 4.8) to get a master plan.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
