import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Bindable var threads: ThreadsViewModel
    @State private var showDoctor = false
    @State private var showTeamDropdown = false
    @State private var showReadiness = false
    @State private var showTeamStudio = false
    @State private var studioInitialRoute: StudioRoute = .clis
    /// Composer "Customize…" deep-link: which team to select when Studio opens.
    @State private var studioCustomizeTeamId: String?
    @State private var showComposeSpecimen = false
    @State private var readinessFocus: String?
    @State private var didLoadCachedSetup = false
    @State private var showMissingDriversAlert = false
    @State private var workspaceMode: WorkspaceMode = .team
    @State private var commands = CommandCenter()
    #if DEBUG
    @State private var showDevSettings = false
    @State private var devBenchScenario: String?
    #endif

    /// SSOT command list — feeds the Actions menu (real ⌘-shortcuts) and the ⌘K
    /// palette. Compose-mode titles/icons read from `ComposeMode` so the menu,
    /// palette, and composer can never disagree.
    private var appCommands: [AppCommand] {
        [
            AppCommand(id: "new-work-order", title: "New work order", symbol: "plus", key: "n") {
                threads.newWorkOrder()
                commands.palettePresented = false
            },
            AppCommand(id: "mode-chat", title: "\(ComposeMode.chat.label) — one model answers", symbol: ComposeMode.chat.icon, key: "1") {
                commands.requestedMode = .chat
                commands.palettePresented = false
            },
            AppCommand(id: "mode-send-to-team", title: "\(ComposeMode.sendToTeam.label) — a team answers", symbol: ComposeMode.sendToTeam.icon, key: "2") {
                commands.requestedMode = .sendToTeam
                commands.palettePresented = false
            },
            AppCommand(id: "mode-exec", title: "\(ComposeMode.exec.label) — an agent builds it", symbol: ComposeMode.exec.icon, key: "3") {
                commands.requestedMode = .exec
                commands.palettePresented = false
            },
            AppCommand(id: "focus-search", title: "Search conversations", symbol: "magnifyingglass", key: "f") {
                commands.focusSearchTick += 1
                commands.palettePresented = false
            },
            AppCommand(id: "rename-thread", title: "Rename thread", symbol: "pencil",
                       key: KeyEquivalent(Character(UnicodeScalar(0xF705)!))) {
                commands.focusRenameTick += 1
                commands.palettePresented = false
            },
            AppCommand(id: "toggle-pin", title: "Pin thread", symbol: "pin", key: "p", modifiers: [.command, .shift]) {
                if let id = threads.selectedThreadId, let thread = threads.selectedThread {
                    threads.togglePin(for: thread)
                }
                commands.palettePresented = false
            },
            AppCommand(id: "archive-thread", title: "Archive thread", symbol: "archivebox", key: "e", modifiers: [.command, .shift]) {
                if let id = threads.selectedThreadId {
                    if threads.showingArchive {
                        threads.unarchiveThread(id)
                    } else {
                        threads.archiveThread(id)
                    }
                }
                commands.palettePresented = false
            },
            AppCommand(id: "command-palette", title: "Command palette", symbol: "command", key: "k", hiddenInPalette: true) {
                commands.palettePresented.toggle()
            },
        ]
    }

    var body: some View {
        Group {
            #if DEBUG
            if GUIFixture.isGrantSession {
                GUIProofGrantView()
            } else {
                workspaceContent
            }
            #else
            workspaceContent
            #endif
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        VStack(spacing: 0) {
            TitleBar(
                showTeamDropdown: $showTeamDropdown,
                showDoctor: $showDoctor,
                onRepair: openReadiness(focus:),
                onManageTeam: openTeamStudio,
                devSimActive: devSimLabel,
                onSettings: openSettings
            )
                .zIndex(10)
            ZStack {
                // The app launches into the clean conversation home. Setup (CLI
                // readiness) and the composer specimen open OVER it on intent;
                // they never hijack launch (founder: no broken/setup garbage on
                // open). Old Team/Threads workspace panes are superseded by the
                // home + routing composer (CR3/CR4 wire conversations live).
                Group {
                    if showTeamStudio {
                        TeamStudioView(
                            initialRoute: studioInitialRoute,
                            customizeTeamId: studioCustomizeTeamId,
                            onDone: { showTeamStudio = false; studioCustomizeTeamId = nil }
                        )
                    } else if showReadiness {
                        TeamReadinessView(
                            focusDriverId: readinessFocus,
                            onClose: { model.markSetupCompleted(); showReadiness = false },
                            onAddSource: { model.markSetupCompleted(); showReadiness = false }
                        )
                    } else if showComposeSpecimen {
                        ComposeSpecimen(
                            openModeMenu: GUIFixture.composeMenuOpen,
                            openTarget: GUIFixture.composeTargetOpen,
                            mode: GUIFixture.composeSpecimenMode
                        )
                    } else {
                        HomeView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showTeamDropdown || showDoctor {
                    ALColor.scrimSubtle
                        .onTapGesture {
                            showTeamDropdown = false
                            showDoctor = false
                        }
                }
            }
        }
        // Pull the custom TitleBar up into the window's titlebar band so the team
        // identity + controls sit on the SAME row as the traffic-light dots
        // (the dots overlay its empty left region), not in a separate band below.
        .ignoresSafeArea(.container, edges: .top)
        .environment(threads)
        .environment(commands)
        .focusedSceneValue(\.appCommands, appCommands)
        .overlay {
            if commands.palettePresented {
                CommandPalette(commands: appCommands) { commands.palettePresented = false }
                    .zIndex(50)
            }
        }
        .background(ALColor.base)
        .overlayPreferenceValue(TeamPillFrameKey.self) { pillFrame in
            GeometryReader { geo in
                if showTeamDropdown, pillFrame != .zero {
                    let origin = geo.frame(in: .global).origin
                    BenchDropdownPanel(
                        isOpen: $showTeamDropdown,
                        attached: true,
                        onRepair: openReadiness(focus:),
                        onManageTeam: openTeamStudio,
                        onOpenSetup: { openReadiness() }
                    )
                    .offset(
                        x: pillFrame.maxX - origin.x - 306,
                        y: pillFrame.maxY - origin.y - 1
                    )
                    .zIndex(20)
                }
            }
            .allowsHitTesting(showTeamDropdown)
        }
        .overlayPreferenceValue(BenchHealthFrameKey.self) { badgeFrame in
            GeometryReader { geo in
                if showDoctor, badgeFrame != .zero {
                    let origin = geo.frame(in: .global).origin
                    let top = badgeFrame.maxY - origin.y - 1
                    // home/doctor.jsx: popover trailing edge inset 13px from window.
                    let maxBody = max(160, geo.size.height - top - 150)
                    BenchHealthPopover(
                        onClose: { showDoctor = false },
                        onOpenFull: { openReadiness() },
                        maxBodyHeight: maxBody
                    )
                    .offset(
                        x: geo.size.width - 404 - 13,
                        y: top
                    )
                    .zIndex(20)
                }
            }
            .allowsHitTesting(showDoctor)
        }
        .onChange(of: commands.customizeTeamRequest) { _, req in
            // Composer "Customize…" → open Studio at this lane's Teams page with
            // the team selected (the editor opens in place). Clear the intent.
            guard let req else { return }
            studioInitialRoute = .teams(req.lane)
            studioCustomizeTeamId = req.teamId
            showTeamStudio = true
            commands.customizeTeamRequest = nil
        }
        .onChange(of: showTeamDropdown) { _, open in
            if open { showDoctor = false }
        }
        .onChange(of: showDoctor) { _, open in
            if open { showTeamDropdown = false }
        }
        .onAppear {
            GlobalHotKey.enable()
            #if DEBUG
            if GUIFixture.isActive {
                // GUI Visual Proof Gate: deep-link the captured state (no probes,
                // no cached load), then self-capture + exit if a PNG was asked
                // for. Designer-mock only — DEBUG + env/file gated.
                if GUIFixture.opensTeamDropdown { showTeamDropdown = true }
                if GUIFixture.opensDoctorPopover { showDoctor = true }
                if GUIFixture.opensReadiness {
                    showReadiness = true
                    readinessFocus = GUIFixture.readinessFocusDriverId
                }
                if GUIFixture.opensComposeSpecimen { showComposeSpecimen = true }
                if GUIFixture.opensTeamStudio {
                    // CLIs page shows a mixed bench (exercises repair); Teams/Skills
                    // pages need a ready bench so the lineup resolves to real models.
                    model.applyDevBenchScenario(GUIFixture.active == "studio-clis" ? "readiness-mixed" : "team-open-ready")
                    studioInitialRoute = GUIFixture.studioRoute
                    showTeamStudio = true
                }
                if GUIFixture.opensCommandPalette { commands.palettePresented = true }
                if GUIFixture.opensHomeWorkspace {
                    model.applyDevBenchScenario(GUIFixture.active ?? "home-with-threads")
                }
                GUIFixture.captureAndExitIfRequested()
                return
            }
            #endif
            if model.isConfigurationBroken {
                showMissingDriversAlert = true
            } else if !didLoadCachedSetup {
                didLoadCachedSetup = true
                // HOTFIX (Launch Authority TCC): cold launch is process-quiet.
                // Render cached/unknown tool state only — never spawn a live
                // resolve/version/smoke sweep here. Live probes require explicit
                // setup/recheck/run intent.
                model.loadCachedSetupState()
                // The app launches into the clean home (founder: never open into
                // the setup page). Setup is reachable on intent via the Team
                // dropdown's "Open CLI setup" + the health badge. First-run
                // auto-open is intentionally NOT done here.
            }
        }
        .alert("Bundled drivers missing", isPresented: $showMissingDriversAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Allnighter could not load driver manifests from the app bundle or embedded defaults. "
                + "Reinstall from a fresh build — do not proceed with a hollow team."
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .allnQuickCapture)) { _ in
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            // Read the clipboard once; fan out to current threads flow (new thread
            // + composer prefill) and the legacy AppModel.prompt path.
            let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            threads.applyQuickCapture(clipboardText: clip)
            model.quickCapture(prefillClipboard: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .allnOpenThreadFromNotification)) { note in
            guard let link = note.object as? ThreadNotificationDeepLink else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            threads.openFromNotification(threadId: link.threadId, turnId: link.turnId)
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        .sheet(isPresented: $showDevSettings) {
            DevSettingsSheet(
                activeScenario: devBenchScenario,
                onUseLiveProbes: useLiveBenchProbes,
                onNavigate: devNavigate(to:scenario:)
            )
        }
        #endif
    }

    #if DEBUG
    private var devSimLabel: String? { devBenchScenario == nil ? nil : "sim" }

    private func openSettings() {
        showDevSettings = true
    }

    private func useLiveBenchProbes() {
        devBenchScenario = nil
        model.loadCachedSetupState()
    }

    private func applyDevScenario(_ scenario: String) {
        devBenchScenario = scenario
        model.applyDevBenchScenario(scenario)
    }

    private func devNavigate(to screen: DevGUIScreen, scenario: String?) {
        showDevSettings = false
        showComposeSpecimen = false
        if let scenario { applyDevScenario(scenario) }
        switch screen {
        case .compose:
            showReadiness = false
            showDoctor = false
            showTeamDropdown = false
        case .routingComposer:
            showReadiness = false
            showDoctor = false
            showTeamDropdown = false
            showComposeSpecimen = true
        case .teamDropdown:
            showReadiness = false
            showDoctor = false
            showTeamDropdown = true
        case .cliSetupPopover:
            showReadiness = false
            showTeamDropdown = false
            showDoctor = true
        case .cliSetupPage:
            showTeamDropdown = false
            showDoctor = false
            readinessFocus = GUIFixture.readinessFocusDriverId(for: scenario ?? devBenchScenario)
            showReadiness = true
        case .firstRunOnboarding:
            // Re-experience first-run: clear the completion flag (so the gating
            // would also fire on the next real launch) and open the onboarding
            // page exactly as a brand-new user lands on it.
            model.resetSetupCompleted()
            showTeamDropdown = false
            showDoctor = false
            readinessFocus = GUIFixture.readinessFocusDriverId(for: scenario ?? devBenchScenario)
            showReadiness = true
        }
    }
    #else
    private var devSimLabel: String? { nil }

    private func openSettings() {}
    #endif

    private func openTeamStudio() {
        showTeamDropdown = false
        showDoctor = false
        showReadiness = false
        showTeamStudio = true
    }

    private func openReadiness(focus: String? = nil) {
        showTeamDropdown = false
        showDoctor = false
        showTeamStudio = false
        readinessFocus = focus ?? model.setupCards.first {
            $0.state != .ready && $0.state != .notInstalled
        }?.driverId ?? model.setupCards.first { $0.state != .ready }?.driverId
        showReadiness = true
    }
}

private struct DetailPane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ALColor.base)
    }

    @ViewBuilder private var content: some View {
        if let history = model.historySelection {
            if history.presetId == "design_board" {
                DesignBoardView()   // read-only board (pick/build gated on no history)
            } else {
                HistoryDetailView(run: history)
            }
        } else if model.run != nil {
            // Run / master-plan content (restyle to RunView/PlanView is the next slice).
            RunResultsView()
        } else {
            ComposeView()
        }
    }
}

// MARK: - Sidebar

private struct TeamSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var showDoctor: Bool

    var body: some View {
        List {
            Section { PresetMenu() }
            Section("Team") {
                ForEach(model.models) { worker in WorkerRow(worker: worker) }
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
        .scrollContentBackground(.hidden)
        .background(ALColor.subtle)
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
                Button("Save current team as preset…") { showSave = true }
                if let active = model.presets.first(where: { $0.id == model.activePresetId }), !active.builtIn {
                    Button("Delete “\(active.displayName)”", role: .destructive) { model.deletePreset(active) }
                }
            } label: {
                Label(model.activePresetName, systemImage: "rectangle.3.group")
            }
            Text(model.workOrderSummary)
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("Save team preset", isPresented: $showSave) {
            TextField("Preset name", text: $name)
            Button("Save") { model.saveCurrentAsPreset(named: name); name = "" }
            Button("Cancel", role: .cancel) { name = "" }
        }
    }
}

private struct WorkerRow: View {
    @Environment(AppModel.self) private var model
    let worker: Model

    var body: some View {
        WorkerChip(
            name: worker.displayName,
            model: model.driverName(for: worker),
            driverId: worker.driverId,
            systemImage: healthSymbol,
            glyphTint: healthTint,
            meta: meta,
            selectable: true,
            selected: model.isSeated(worker),
            onToggle: { model.toggle(worker) }
        )
        .listRowInsets(EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4))
        .listRowBackground(Color.clear)
    }

    private var meta: String? {
        var parts: [String] = []
        if model.seatCount(for: worker) > 1 { parts.append("×\(model.seatCount(for: worker))") }
        if model.planWriterModel?.id == worker.id { parts.append("judge") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // Health still surfaces in Doctor; here it just tints the glyph so a broken
    // CLI reads at a glance without faking a run status.
    private var healthSymbol: String {
        switch model.diagnosis(for: worker.id)?.health {
        case .unhealthy: "exclamationmark.triangle.fill"
        case .unknown: "hand.raised"
        default: "cpu"
        }
    }
    private var healthTint: Color {
        switch model.diagnosis(for: worker.id)?.health {
        case .healthy: ALColor.statusDone
        case .unhealthy: ALColor.statusTimeout
        default: ALColor.textSecondary
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
    let run: TeamRun
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
    let run: TeamRun
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
                if let plan = run.plan, !plan.isEmpty {
                    GroupBox("Plan") {
                        Text(plan).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { copy(RunMarkdown.bundle(run, models: model.models)) } label: { Label("Copy full bundle", systemImage: "tray.and.arrow.up") }
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
                Text("\(model.expandedWorkers.count) workers selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.isRunning {
                    Button(role: .destructive) { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                } else {
                    Button { model.runTeam() } label: { Label("Run team", systemImage: "play.fill") }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.expandedWorkers.isEmpty)
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
                "No team run yet",
                systemImage: "person.3.sequence",
                description: Text("Type a prompt and run the team. Every worker answers in parallel.")
            )
        }
    }
}

private struct VerdictStrip: View {
    let run: TeamRun
    var body: some View {
        let answered = run.workerAnswers.filter(\.hasAnswer).count
        HStack(spacing: 8) {
            ForEach(run.workerAnswers) { member in
                HStack(spacing: 4) {
                    StatusDot(status: member.status)
                    Text(member.workerId.replacingOccurrences(of: "worker_", with: "")).font(.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
            }
            Spacer()
            if let a = run.analysis {
                Text("\(answered)/\(run.workerAnswers.count) · \(a.consensus.count) consensus · \(a.contradictions.count) conflicts · \(a.blindSpots.count) gaps")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AnalysisCard: View {
    @Environment(AppModel.self) private var model
    let run: TeamRun
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
                    if !a.failedWorkers.isEmpty {
                        Text("Did not answer: " + a.failedWorkers.map { model.seatDisplayName($0.workerId, in: run) }.joined(separator: ", "))
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
    let run: TeamRun
    @State private var pastedPlan = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Plan", systemImage: "doc.text.magnifyingglass").font(.title3.bold())
                Spacer()
                if run.plan != nil {
                    Button { copy(model.planMarkdown()) } label: { Label("Copy plan", systemImage: "doc.on.doc") }
                    Button { copy(model.bundleMarkdown()) } label: { Label("Copy full bundle", systemImage: "tray.and.arrow.up") }
                }
            }
            content
            if let dir = model.lastSavedDirectory, run.plan != nil {
                Text("Saved to \(dir.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.25)))
    }

    @ViewBuilder private var content: some View {
        if let plan = run.plan, !plan.isEmpty {
            Text(plan).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        } else if run.status == .planning {
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
            Label("Synthesis did not produce a plan. The analysis and worker answers are still available.", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        } else if run.status == .answersIn {
            Text("No plan writer is on the team. Add a model that can write the plan (e.g. Opus 4.8).")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
    private func copy(_ t: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string) }
}

// MARK: - Review board + final spec (RB2/RB3)

private struct ReviewActions: View {
    @Environment(AppModel.self) private var model
    let run: TeamRun
    var body: some View {
        if run.plan != nil && model.latestReviews.isEmpty && model.finalSpec == nil {
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
                    Picker("Worker", selection: Binding(get: { model.dispatchWorkerId ?? model.planWriterModel?.id ?? "" }, set: { model.dispatchWorkerId = $0 })) {
                        ForEach(model.models) { w in Text(w.displayName).tag(w.id) }
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
    let run: TeamRun
    var body: some View {
        DisclosureGroup("Worker answers (\(run.workerAnswers.count))") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(run.workerAnswers) { member in
                    MemberCard(member: member, name: model.seatDisplayName(member.workerId, in: run))
                }
            }.padding(.top, 6)
        }.font(.headline)
    }
}

private struct StatusDot: View {
    let status: WorkerAnswerStatus
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
    let member: WorkerAnswer
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
            Button("Use this answer") { model.setManualAnswer(workerId: member.workerId, text: pasted) }
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
            Text("Detects each model's CLI, checks the version, and runs a smoke test. A broken or updated CLI fails loudly here with a fix — it never silently drops from the bench.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.models) { worker in
                        DoctorRow(worker: worker, diagnosis: model.diagnosis(for: worker.id))
                    }
                    if !model.scorecards.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text("Worker scorecards (from local history — estimates)").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(model.scorecards) { card in
                            let name = model.models.first { $0.id == card.workerId }?.displayName ?? card.workerId
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
    let worker: Model
    let diagnosis: ModelDiagnosis?
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

// MARK: - Title bar (chrome.jsx .alk-title)

private struct TitleBar: View {
    @Binding var showTeamDropdown: Bool
    @Binding var showDoctor: Bool
    var onRepair: (String) -> Void
    var onManageTeam: () -> Void
    var devSimActive: String?
    var onSettings: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            // Centered identity: live mark + alln · team
            HStack(spacing: 8) {
                LiveMark(state: model.isRunning ? .running : .idle, size: 16)
                Text("alln").font(ALFont.label.weight(.semibold)).foregroundStyle(ALColor.textSecondary)
                Text("· team").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                if let devSimActive {
                    Badge(text: devSimActive, tone: .warning, dot: true, mono: true)
                }
            }
            // Right controls
            HStack(spacing: 6) {
                Spacer()
                BenchHealthBadge(isOpen: $showDoctor)
                TeamControlView(
                    isOpen: $showTeamDropdown,
                    onRepair: onRepair,
                    onManageTeam: onManageTeam
                )
                IconButton(systemImage: "clock.arrow.circlepath", accessibilityLabel: "History", small: true) {}
                IconButton(systemImage: "slider.horizontal.3", accessibilityLabel: settingsLabel, small: true, action: onSettings)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: ALControl.titleBarHeight, alignment: .top)
        .background(WindowDragArea())
        .background(ALColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private var settingsLabel: String {
        #if DEBUG
        return "Developer — GUI routes"
        #else
        return "Settings"
        #endif
    }
}

/// Makes an area drag the window (hidden title bar needs an explicit drag region).
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

// MARK: - Sidebar (chrome.jsx .alk-side)

private struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            // PANEL
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Team", trailing: "\(model.rosterModelIds.count) of \(model.models.count)")
                VStack(spacing: 6) {
                    ForEach(model.models) { worker in
                        WorkerChip(
                            name: worker.displayName,
                            model: "via " + model.driverName(for: worker).replacingOccurrences(of: "_", with: "-"),
                            driverId: worker.driverId,
                            systemImage: glyphSymbol(for: worker),
                            glyphTint: glyphTint(for: worker),
                            meta: model.seatCount(for: worker) > 1 ? "×\(model.seatCount(for: worker))" : nil,
                            selectable: true,
                            selected: model.isSeated(worker),
                            onToggle: { model.toggle(worker) }
                        )
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 8)

            // SYNTHESIZER
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("PlanWriter", trailing: nil)
                synthRow
            }
            .padding(.horizontal, 14).padding(.bottom, 8)

            Spacer(minLength: 0)

            // RECENT (pinned bottom)
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Recent", trailing: nil)
                if model.history.isEmpty {
                    Text("No runs yet").font(ALFont.caption).foregroundStyle(ALColor.textFaint)
                        .padding(.vertical, 2)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.history.prefix(8)) { run in
                            RecentRow(run: run) { model.openHistory(run) }
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ALColor.subtle)
    }

    private var synthRow: some View {
        HStack(spacing: 10) {
            WorkerGlyph(driverId: model.planWriterModel?.driverId,
                        systemImage: model.planWriterModel.map { glyphSymbol(for: $0) } ?? "cpu",
                        tint: model.planWriterModel.map { glyphTint(for: $0) } ?? ALColor.textSecondary,
                        size: 26)
            Text(model.planWriterModel?.displayName ?? "None")
                .font(ALFont.body.weight(.semibold)).foregroundStyle(ALColor.textPrimary)
            Spacer(minLength: 6)
            Text("master").font(ALFont.monoSm).foregroundStyle(ALColor.accentText)
            Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(ALFont.caption.weight(.bold)).tracking(ALTracking.caps)
                .foregroundStyle(ALColor.textFaint)
            Spacer()
            if let trailing {
                Text(trailing).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
        }
        .padding(.bottom, 10)
    }

    // Brand-glyph approximation via SF Symbols (real Simple Icons SVGs = follow-up).
    private func glyphSymbol(for w: Model) -> String {
        let d = model.driverName(for: w).lowercased()
        let n = w.displayName.lowercased()
        if d.contains("gemini") { return "sparkle" }
        if d.contains("codex") || n.contains("chatgpt") || n.contains("gpt") { return "terminal" }
        if d.contains("cursor") || n.contains("composer") { return "squareshape" }
        if d.contains("grok") || n.contains("grok") { return "bolt.fill" }
        return "cpu" // claude / opus / sonnet / default
    }
    private func glyphTint(for w: Model) -> Color {
        if model.planWriterModel?.id == w.id { return ALColor.accent }
        if case .unhealthy = model.diagnosis(for: w.id)?.health { return ALColor.statusTimeout }
        return ALColor.textSecondary
    }
}

private struct RecentRow: View {
    let run: TeamRun
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(run.prompt).font(ALFont.label).foregroundStyle(ALColor.textSecondary).lineLimit(1)
                    Text(metaText).font(.system(size: 9, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? ALColor.hover : .clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var dotColor: Color {
        switch run.status {
        case .complete: ALColor.statusDone
        case .partial, .failed: ALColor.statusTimeout
        default: ALColor.textFaint
        }
    }
    private var metaText: String {
        let done = run.workerAnswers.filter { $0.status == .done }.count
        return "\(run.createdAt.formatted(.dateTime.hour().minute())) · \(done) done"
    }
}

// MARK: - Compose (screens.jsx Composer)

private struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var promptFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            Text("New team run")
                .font(ALFont.caption.weight(.bold)).tracking(1.1).textCase(.uppercase)
                .foregroundStyle(ALColor.accentText)
                .padding(.bottom, 14)

            // Prompt card
            VStack(spacing: 0) {
                TextEditor(text: $model.prompt)
                    .focused($promptFocused)
                    .font(.system(size: 18))
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92, maxHeight: 220)
                    .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 12)
                    .overlay(alignment: .topLeading) {
                        if model.prompt.isEmpty {
                            Text("Ask the team one thing…")
                                .font(.system(size: 18)).foregroundStyle(ALColor.textFaint)
                                .padding(.leading, 23).padding(.top, 26)
                                .allowsHitTesting(false)
                        }
                    }
                HStack {
                    Text("\(model.expandedWorkers.count) workers · local · $0 marginal")
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                    Spacer()
                    Button { model.runTeam() } label: { Label("Run team", systemImage: "play.fill") }
                        .buttonStyle(.alPrimary)
                        .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.expandedWorkers.isEmpty)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
            }
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.xl))
            .overlay {
                RoundedRectangle(cornerRadius: ALRadius.xl)
                    .strokeBorder(promptFocused ? ALColor.accentBorder : ALColor.borderDefault, lineWidth: 1)
            }
            .alShadowSm()

            // Example chips
            HStack(spacing: 8) {
                ForEach(Self.examples, id: \.self) { ex in
                    Button { model.prompt = ex } label: {
                        Text(ex).font(ALFont.label).foregroundStyle(ALColor.textMuted)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(ALColor.surface, in: Capsule())
                            .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 32)
    }

    private static let examples = [
        "3 directions for a premium dashboard",
        "rewrite our API error copy",
        "plan a migration to Swift 6",
    ]
}

// MARK: - Workspace switcher (Council ↔ Threads)

enum WorkspaceMode: String, CaseIterable { case team, threads }

private struct WorkspaceSwitcher: View {
    @Binding var mode: WorkspaceMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(WorkspaceMode.allCases, id: \.self) { item in
                Button { mode = item } label: {
                    Text(item == .team ? "Team" : "Threads")
                        .font(ALFont.label.weight(.semibold))
                        .foregroundStyle(mode == item ? ALColor.textOnAmber : ALColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(mode == item ? ALColor.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: ALRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(ALColor.subtle)
    }
}
