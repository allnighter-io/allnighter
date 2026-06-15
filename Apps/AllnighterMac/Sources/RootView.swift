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
                .navigationSplitViewColumnWidth(min: 270, ideal: 290)
        } detail: {
            DetailPane()
        }
        .sheet(isPresented: $showDoctor) { DoctorView() }
        .onAppear { GlobalHotKey.enable() }
        .onReceive(NotificationCenter.default.publisher(for: .allnighterQuickCapture)) { _ in
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            model.quickCapture(prefillClipboard: true)
        }
    }
}

private struct DetailPane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let history = model.historySelection {
            HistoryDetailView(run: history)
        } else {
            VStack(spacing: 0) {
                ModePicker()
                Divider()
                if model.designMode {
                    DesignComposer()
                    Divider()
                    DesignBoardView()
                } else {
                    PromptComposer()
                    Divider()
                    RunResultsView()
                }
            }
        }
    }
}

// MARK: - Sidebar

private struct PanelSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var showDoctor: Bool

    var body: some View {
        List {
            Section { PresetMenu() }
            Section("Panel") {
                ForEach(model.workers) { worker in WorkerRow(worker: worker) }
            }
            Section {
                Button {
                    model.runDoctor(); showDoctor = true
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

private struct PresetMenu: View {
    @Environment(AppModel.self) private var model
    @State private var showSave = false
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(model.presets) { preset in
                    Button {
                        model.apply(preset)
                    } label: {
                        if model.activePresetId == preset.id { Label(preset.displayName, systemImage: "checkmark") }
                        else { Text(preset.displayName) }
                    }
                }
                Divider()
                Button("Save current panel as preset…") { showSave = true }
                if let active = model.presets.first(where: { $0.id == model.activePresetId }), !active.builtIn {
                    Button("Delete “\(active.displayName)”", role: .destructive) { model.deletePreset(active) }
                }
            } label: {
                Label(model.activePresetName, systemImage: "rectangle.3.group")
            }
            let plan = model.callPlan
            Text("\(model.expandedSeats.count) seats · judge: \(model.judgeWorker?.displayName ?? "none") · est. \(plan.estimatedCalls) calls (\(plan.quotaRisk))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("Save panel preset", isPresented: $showSave) {
            TextField("Preset name", text: $name)
            Button("Save") { model.saveCurrentAsPreset(named: name); name = "" }
            Button("Cancel", role: .cancel) { name = "" }
        }
    }
}

private struct WorkerRow: View {
    @Environment(AppModel.self) private var model
    let worker: Worker

    var body: some View {
        HStack(spacing: 8) {
            Button { model.toggle(worker) } label: {
                Image(systemName: model.isSeated(worker) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.isSeated(worker) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(worker.displayName).font(.body)
                    if model.seatCount(for: worker) > 1 {
                        Text("×\(model.seatCount(for: worker))").font(.caption2).foregroundStyle(.secondary)
                    }
                    if model.judgeWorker?.id == worker.id {
                        Image(systemName: "gavel").font(.caption2).foregroundStyle(.secondary).help("Judge")
                    }
                }
                Text(model.driverName(for: worker)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            healthBadge
        }
    }

    @ViewBuilder private var healthBadge: some View {
        if let d = model.diagnosis(for: worker.id) {
            switch d.health {
            case .healthy: Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).help(d.version ?? "Healthy")
            case .unhealthy(let reason): Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(d.fixHint ?? reason)
            case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help("Manual / unknown")
            }
        }
    }
}

// MARK: - History

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
                    }.buttonStyle(.plain)
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
            Text(run.prompt).font(.callout).lineLimit(1)
            HStack(spacing: 6) {
                Text(run.createdAt, format: .dateTime.month().day().hour().minute())
                Text("·"); Text(run.status.rawValue).foregroundStyle(statusColor)
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading)
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
                        Text(run.createdAt, format: .dateTime.year().month().day().hour().minute()).font(.headline)
                    }
                    Spacer()
                    Button { model.runAgain(run) } label: { Label("Run again", systemImage: "arrow.clockwise") }.disabled(model.isRunning)
                    Button { model.closeHistory() } label: { Label("Close", systemImage: "xmark") }
                }
                GroupBox("Prompt") {
                    Text(run.prompt).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                if run.analysis != nil { AnalysisCard(run: run) }
                if let plan = run.masterPlan, !plan.isEmpty {
                    GroupBox("Master Plan") {
                        Text(plan).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { copy(RunMarkdown.bundle(run, workers: model.workers)) } label: { Label("Copy full bundle", systemImage: "tray.and.arrow.up") }
                }
                ReviewBoardCard()
                FinalSpecCard()
                MembersDisclosure(run: run)
            }
            .padding()
        }
    }
    private func copy(_ t: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string) }
}

// MARK: - Composer

private struct PromptComposer: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt").font(.headline)
            TextEditor(text: $model.prompt)
                .font(.body).frame(minHeight: 90, maxHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Text("\(model.expandedSeats.count) seats selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.isRunning {
                    Button(role: .destructive) { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                } else {
                    Button { model.runCouncil() } label: { Label("Run council", systemImage: "play.fill") }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.expandedSeats.isEmpty)
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
                    VerdictStrip(run: run)
                    if run.analysis != nil { AnalysisCard(run: run) }
                    MasterPlanCard(run: run)
                    ReviewActions(run: run)
                    ReviewBoardCard()
                    FinalSpecCard()
                    DispatchCard()
                    MembersDisclosure(run: run)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No council yet",
                systemImage: "person.3.sequence",
                description: Text("Type a prompt and run the council. Every seat answers in parallel.")
            )
        }
    }
}

private struct VerdictStrip: View {
    let run: CouncilRun
    var body: some View {
        let answered = run.members.filter(\.hasAnswer).count
        HStack(spacing: 8) {
            ForEach(run.members) { member in
                HStack(spacing: 4) {
                    StatusDot(status: member.status)
                    Text(member.seatId.replacingOccurrences(of: "worker_", with: "")).font(.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
            }
            Spacer()
            if let a = run.analysis {
                Text("\(answered)/\(run.members.count) · \(a.consensus.count) consensus · \(a.contradictions.count) conflicts · \(a.blindSpots.count) gaps")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AnalysisCard: View {
    @Environment(AppModel.self) private var model
    let run: CouncilRun
    @State private var expanded = true
    var body: some View {
        if let a = run.analysis {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    section("Consensus", a.consensus.map(\.statement))
                    if !a.contradictions.isEmpty {
                        Text("Conflicts").font(.subheadline.bold())
                        ForEach(Array(a.contradictions.enumerated()), id: \.offset) { _, c in
                            Text("• \(c.topic) → \(c.recommendedResolution)").font(.callout)
                        }
                    }
                    section("Unique insights", a.uniqueInsights.map(\.statement))
                    section("Blind spots & gaps", a.blindSpots)
                    if !a.failedSeats.isEmpty {
                        Text("Did not answer: " + a.failedSeats.map { model.seatDisplayName($0.seatId, in: run) }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding(.top, 4)
            } label: {
                Label("Judge Analysis", systemImage: "rectangle.and.text.magnifyingglass").font(.headline)
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
    @ViewBuilder private func section(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                    Text("• \(s)").font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct MasterPlanCard: View {
    @Environment(AppModel.self) private var model
    let run: CouncilRun
    @State private var pastedPlan = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Master Plan", systemImage: "doc.text.magnifyingglass").font(.title3.bold())
                Spacer()
                if run.masterPlan != nil {
                    Button { copy(model.masterPlanMarkdown()) } label: { Label("Copy plan", systemImage: "doc.on.doc") }
                    Button { copy(model.bundleMarkdown()) } label: { Label("Copy full bundle", systemImage: "tray.and.arrow.up") }
                }
            }
            content
            if let dir = model.lastSavedDirectory, run.masterPlan != nil {
                Text("Saved to \(dir.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.25)))
    }

    @ViewBuilder private var content: some View {
        if let plan = run.masterPlan, !plan.isEmpty {
            Text(plan).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        } else if run.status == .synthesizing {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Synthesizing (analysis → plan)…") }
        } else if let manual = model.manualSynthesisPrompt {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your judge is a manual worker. Run this prompt in its app, then paste the analysis + plan:")
                    .font(.callout).foregroundStyle(.secondary)
                Button { copy(manual) } label: { Label("Copy synthesis prompt", systemImage: "doc.on.doc") }
                TextEditor(text: $pastedPlan).frame(minHeight: 80).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Button("Use this result") { model.setManualSynthesis(pastedPlan) }
                    .disabled(pastedPlan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else if run.status == .partial {
            Label("Synthesis did not produce a plan. The analysis and member answers are still available.", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        } else if run.status == .answersIn {
            Text("No judge is seated. Add a worker that can synthesize (e.g. Opus 4.8).")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
    private func copy(_ t: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string) }
}

// MARK: - Review board + final spec (RB2/RB3)

private struct ReviewActions: View {
    @Environment(AppModel.self) private var model
    let run: CouncilRun
    var body: some View {
        if run.masterPlan != nil && model.latestReviews.isEmpty && model.finalSpec == nil {
            HStack(spacing: 8) {
                if model.isReviewing {
                    ProgressView().controlSize(.small)
                    Text(run.status == .finalizing ? "Finalizing…" : "Running review board…").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Pressure-test this plan:").font(.callout).foregroundStyle(.secondary)
                    Button { model.runReviewBoard(lensIds: AppModel.lightReviewLenses) } label: { Label("Light review", systemImage: "checklist") }
                    Button { model.runReviewBoard(lensIds: AppModel.fullReviewLenses) } label: { Label("Full review", systemImage: "checklist.checked") }
                }
            }
        }
    }
}

private struct ReviewBoardCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let reviews = model.latestReviews
        if !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Review Board (\(reviews.count))", systemImage: "person.2.badge.gearshape").font(.title3.bold())
                ForEach(reviews) { review in
                    DisclosureGroup(review.payload?.review?.lensId ?? review.promptProfileId ?? review.id) {
                        Text(review.payload?.markdown ?? review.errorReason ?? "")
                            .font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                }
            }
            .padding().background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct FinalSpecCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let final = model.finalSpec {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Final Spec", systemImage: "doc.badge.gearshape").font(.title3.bold())
                    Spacer()
                    Button { copy(final.markdown) } label: { Label("Copy", systemImage: "doc.on.doc") }
                }
                HStack(spacing: 6) {
                    chip(final.hasProofCommands ? "Proof commands ✓" : "No proof commands", final.hasProofCommands ? .green : .orange)
                    if !final.reviewBoardRan { chip("No review board", .secondary) }
                    if !final.decisionsStructured { chip("Decisions unstructured", .orange) }
                }
                Text(final.markdown).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if !final.reviewDecisions.isEmpty {
                    Text("Review decisions").font(.subheadline.bold())
                    ForEach(Array(final.reviewDecisions.enumerated()), id: \.offset) { _, d in
                        Text("• \(d.lensId): \(d.decision.rawValue.uppercased()) — \(d.reason)").font(.caption)
                    }
                }
            }
            .padding()
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.25)))
        }
    }
    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
    }
    private func copy(_ t: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string) }
}

// MARK: - Direct dispatch (RB4)

private struct DispatchCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        if model.canDispatch {
            VStack(alignment: .leading, spacing: 8) {
                Label("Implement This", systemImage: "paperplane").font(.title3.bold())
                Text(ImplementationBrief.defaultBoundary).font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Working directory", text: $model.dispatchWorkingDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button { pickFolder() } label: { Image(systemName: "folder") }.help("Choose folder")
                }
                HStack {
                    Picker("Worker", selection: Binding(get: { model.dispatchWorkerId ?? model.judgeWorker?.id ?? "" }, set: { model.dispatchWorkerId = $0 })) {
                        ForEach(model.workers) { w in Text(w.displayName).tag(w.id) }
                    }.frame(maxWidth: 220)
                    Toggle("Reveal only", isOn: $model.dispatchRevealOnly)
                    Spacer()
                    if model.isDispatching {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { model.dispatch() } label: { Label("Dispatch", systemImage: "play.fill") }
                            .disabled(model.dispatchWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                ForEach(model.dispatches) { d in
                    if let ret = d.payload?.executionReturn {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dispatch \(ret.dispatchIndex) · \(ret.executionWorkerId) · \(ret.status.rawValue)")
                                .font(.caption.bold())
                            if let excerpt = ret.transcriptExcerpt, !excerpt.isEmpty {
                                Text(excerpt).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    .lineLimit(6).textSelection(.enabled)
                            }
                        }
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                ReturnReviewSection()
            }
            .padding().background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.dispatchWorkingDirectory = url.path
        }
    }
}

private struct ReturnReviewSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let hasDoneDispatch = model.dispatches.contains { $0.payload?.executionReturn?.status == .done }
        if hasDoneDispatch {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Return review").font(.caption.bold())
                    Spacer()
                    if model.isReturnReviewing { ProgressView().controlSize(.small) }
                    else if model.returnReview == nil {
                        Button { model.runReturnReview() } label: { Label("Evaluate result", systemImage: "checkmark.circle") }
                            .controlSize(.small)
                    }
                }
                if let rr = model.returnReview {
                    Text(rr.markdown).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(10)
                    if let rec = rr.recommendation {
                        Text("Recommendation: \(rec.action.rawValue.uppercased()) — \(rec.reasoning)").font(.caption.bold())
                    }
                }
                if let score = model.outcomeScore {
                    Text("Outcome score: \(String(format: "%.1f", score.totalWeighted)) (\(score.pass ? "pass" : "below bar")) · estimate")
                        .font(.caption2).foregroundStyle(score.pass ? .green : .orange)
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct MembersDisclosure: View {
    @Environment(AppModel.self) private var model
    let run: CouncilRun
    var body: some View {
        DisclosureGroup("Member answers (\(run.members.count))") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(run.members) { member in
                    MemberCard(member: member, name: model.seatDisplayName(member.seatId, in: run))
                }
            }.padding(.top, 6)
        }.font(.headline)
    }
}

private struct StatusDot: View {
    let status: MemberStatus
    var body: some View { Circle().fill(color).frame(width: 8, height: 8) }
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
    let name: String
    @State private var pasted = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusDot(status: member.status)
                Text(name).font(.headline)
                Spacer()
                if let ms = member.durationMs {
                    Text(String(format: "%.1fs", Double(ms) / 1000)).font(.caption).foregroundStyle(.secondary)
                }
                if member.output != nil {
                    Button { copy(member.output ?? "") } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy answer")
                }
            }
            switch member.status {
            case .done:
                Text(member.output ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            case .running, .queued:
                ProgressView().controlSize(.small)
            case .skipped:
                manualPasteBox
            case .failed, .timedOut:
                Label(member.errorReason ?? member.status.rawValue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            case .cancelled:
                Text("Cancelled").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding().background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var manualPasteBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Manual worker — run this prompt in its app and paste the answer:").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $pasted).frame(minHeight: 60).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Button("Use this answer") { model.setManualAnswer(seatId: member.seatId, text: pasted) }
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    private func copy(_ t: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string) }
}

// MARK: - Doctor

private struct DoctorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Doctor", systemImage: "stethoscope").font(.title2.bold())
                Spacer()
                Button { model.runDoctor() } label: { Label(model.isDoctorRunning ? "Checking…" : "Re-run", systemImage: "arrow.clockwise") }.disabled(model.isDoctorRunning)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Detects each worker's CLI, checks the version, and runs a smoke test. A broken or updated CLI fails loudly here with a fix — it never silently drops from the panel.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.workers) { worker in
                        DoctorRow(worker: worker, diagnosis: model.diagnosis(for: worker.id))
                    }
                    if !model.scorecards.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text("Worker scorecards (from local history — estimates)").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(model.scorecards) { card in
                            let name = model.workers.first { $0.id == card.workerId }?.displayName ?? card.workerId
                            Text("\(name): answer \(pct(card.panelAnswerRate)), judge \(pct(card.judgeSuccessRate)), exec \(pct(card.executionSuccessRate))\(card.hasEnoughData ? "" : "  (insufficient data)")")
                                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding().frame(minWidth: 520, minHeight: 420)
    }
    private func pct(_ v: Double) -> String { "\(Int(v * 100))%" }
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
                    Text(diagnosis?.driverName ?? worker.driverId).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let v = diagnosis?.version {
                    Text(v).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            if let hint = diagnosis?.fixHint {
                HStack(alignment: .top, spacing: 6) {
                    Text(hint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hint, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy fix hint")
                }
            }
        }
        .padding(10).background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
    @ViewBuilder private var icon: some View {
        switch diagnosis?.health {
        case .healthy: Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        case .unhealthy: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unknown: Image(systemName: "hand.raised").foregroundStyle(.secondary)
        case .none: ProgressView().controlSize(.small)
        }
    }
}
