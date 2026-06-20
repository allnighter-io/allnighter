import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ProjectsViewModel.self) private var projects
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
    @State private var workspaceMode: WorkspaceMode = .inbox
    @State private var showPending = false
    /// Title-bar pending-count source (drives the conditional `N pending` pill).
    @State private var pendingVM: PendingViewModel?
    @State private var commands = CommandCenter()
    /// DEBUG GUI-proof only: render the Factory Floor reader over a sample run.
    @State private var showFloorReaderProof = false
    #if DEBUG
    @State private var showDevSettings = false
    @State private var devBenchScenario: String?
    #endif

    /// SSOT command list — feeds the Actions menu (real ⌘-shortcuts) and the ⌘K palette.
    private var appCommands: [AppCommand] {
        [
            AppCommand(id: "new-run", title: "New Chat", symbol: "plus", key: "n") {
                threads.newRun()
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

    /// Pending screen data source — the fixture's seeded store under proof, else real.
    private var pendingService: PendingService {
        GUIFixture.seededPendingService(models: model.models)
            ?? PendingService(store: PendingStore(), models: model.models)
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
    private var floorReaderProofView: some View {
        #if DEBUG
        FactoryFloorView(run: FloorReaderSample.run, onBack: { showFloorReaderProof = false })
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private var workspaceContent: some View {
        VStack(spacing: 0) {
            TitleBar(
                showTeamDropdown: $showTeamDropdown,
                showDoctor: $showDoctor,
                workspaceMode: $workspaceMode,
                pendingCount: pendingVM?.totalPending ?? 0,
                onRepair: openReadiness(focus:),
                onManageTeam: openTeamStudio,
                onOpenPending: { showPending = true },
                devSimActive: devSimLabel,
                onSettings: openSettings
            )
                .zIndex(10)
                .onAppear { if pendingVM == nil { pendingVM = PendingViewModel(service: pendingService) } }
            ZStack {
                // The app launches into the clean conversation home. Setup (CLI
                // readiness) and the composer specimen open OVER it on intent;
                // they never hijack launch (founder: no broken/setup garbage on
                // open). Old Team/Threads workspace panes are superseded by the
                // home + routing composer (CR3/CR4 wire conversations live).
                Group {
                    if showFloorReaderProof {
                        floorReaderProofView
                    } else if GUIFixture.opensPending || showPending {
                        PendingView(service: pendingService, onClose: {
                            showPending = false
                            pendingVM?.refresh()
                        })
                    } else if showTeamStudio {
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
                            openTarget: GUIFixture.composeTargetOpen,
                            team: GUIFixture.composeTeamId,
                            initialText: GUIFixture.composeFileReferenceOpen ? "@Com" : ""
                        )
                    } else if workspaceMode == .teams {
                        // Teams workspace — the Send-to-team launcher (G-T1 brings
                        // full fidelity; G-T0 wires the toggle + a real card roster).
                        TeamsLauncherView(
                            onContinue: { workspaceMode = .inbox },
                            onAddTeam: { workspaceMode = .inbox; openTeamStudio() }
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
                    // Leave generous bottom room so the footer button + last row
                    // always clear the window edge (no cramped half-row).
                    let maxBody = max(160, geo.size.height - top - 190)
                    BenchHealthPopover(
                        onClose: { showDoctor = false },
                        // Open the full Settings shell at CLIs (sidebar present) so
                        // Teams/Skills stay reachable — not the sidebarless page.
                        onOpenFull: { showDoctor = false; openTeamStudio() },
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
                if GUIFixture.opensTeamsLauncher {
                    model.applyDevBenchScenario("team-open-ready")
                    workspaceMode = .teams
                }
                if GUIFixture.opensFloorReader {
                    model.applyDevBenchScenario("team-open-ready")
                    showFloorReaderProof = true
                }
                if GUIFixture.opensHomeWorkspace {
                    model.applyDevBenchScenario(GUIFixture.active ?? "home-with-threads")
                }
                if GUIFixture.opensProjectsRail {
                    projects.seedForProof(ProjectsViewModel.sampleProjects(), active: "prj_halo")
                    threads.currentProjectId = "prj_halo"
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
            // New threads bind to the active project (PRJ-S14).
            threads.currentProjectId = projects.activeProjectId
        }
        .onChange(of: projects.activeProjectId) { _, id in
            threads.currentProjectId = id
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
        var shell = RootDebugRouting.ShellState(
            showDevSettings: showDevSettings,
            showComposeSpecimen: showComposeSpecimen,
            showReadiness: showReadiness,
            showDoctor: showDoctor,
            showTeamDropdown: showTeamDropdown,
            readinessFocus: readinessFocus
        )
        RootDebugRouting.navigate(
            to: screen,
            scenario: scenario,
            devBenchScenario: devBenchScenario,
            state: &shell,
            applyScenario: applyDevScenario,
            resetSetupCompleted: model.resetSetupCompleted
        )
        showDevSettings = shell.showDevSettings
        showComposeSpecimen = shell.showComposeSpecimen
        showReadiness = shell.showReadiness
        showDoctor = shell.showDoctor
        showTeamDropdown = shell.showTeamDropdown
        readinessFocus = shell.readinessFocus
    }
    #else
    private var devSimLabel: String? { nil }

    /// Release: the title-bar gear opens the Settings shell (sidebar: CLIs · Teams ·
    /// Skills). Was a no-op — the regression that orphaned the whole settings page.
    private func openSettings() { openTeamStudio() }
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
