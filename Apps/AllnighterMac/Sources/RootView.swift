import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(RemoteAccountModel.self) private var remoteAccount
    @Environment(ProjectsViewModel.self) private var projects
    @Environment(ReleaseUpdateModel.self) private var releaseUpdates
    @Environment(EntitlementModel.self) private var entitlement
    @Environment(\.openWindow) private var openWindow
    @Bindable var threads: ThreadsViewModel
    @State private var showDoctor = false
    @State private var showTeamDropdown = false
    @State private var showReadiness = false
    @State private var showTeamStudio = false
    @State private var studioInitialRoute: StudioRoute = .clis
    /// Composer "Customize…" deep-link: which team to select when Studio opens.
    @State private var studioCustomizeTeamId: String?
    /// Add-team flow: open Team Studio straight into a new blank team draft.
    @State private var studioStartNewTeam = false
    /// Deep-link from CLI health popover → Settings CLIs page with this driver selected.
    @State private var studioCLIFocusDriverId: String?
    @State private var showComposeSpecimen = false
    @State private var readinessFocus: String?
    @State private var didLoadCachedSetup = false
    @State private var showMissingDriversAlert = false
    @State private var workspaceMode: WorkspaceMode = .inbox
    @State private var showPending = false
    /// The Factory Floor reader open over the workspace (a deep surface). Owned here so a
    /// top-bar route command can dismiss it (HomeView renders it via this binding).
    @State private var floorRun: TeamRun?
    /// R-S08: which project's Loop launch sheet is open (mirrors `floorRun`'s
    /// RootView-owned shape) — a "Start relay" tap in the sidebar, or a GUI-proof
    /// deep-link (`GUIFixture.opensRelayLaunch`), sets this.
    @State private var relayLaunchRequest: RelayLaunchRequest?
    /// Title-bar pending-count source (drives the conditional `N pending` pill).
    @State private var pendingVM: PendingViewModel?
    @State private var commands = CommandCenter()
    /// R-S08: resume-from-GUI for an escalated relay thread (`RelayEscalationRow` in
    /// ThreadView.swift). One shared instance so repeated resumes across relay threads
    /// share in-flight/error state, mirroring `commands`'s app-wide singleton shape.
    @State private var relayResume = RelayResumeController()
    /// ATL-S04: founder Stop from relay thread chrome (`RelayThreadChrome`).
    @State private var relayStop = RelayStopController()
    /// DEBUG GUI-proof only: render the Factory Floor reader over a sample run.
    @State private var showFloorReaderProof = false
    @State private var pairingPromptRequest: RemotePairRequest?
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
            AppCommand(id: "focus-composer", title: "Focus composer", symbol: "text.cursor", key: "l") {
                commands.focusComposerTick += 1
                commands.palettePresented = false
            },
            AppCommand(id: "go-inbox", title: "Go to Inbox", symbol: "tray", key: "1") {
                routeTo(.inbox)
                commands.palettePresented = false
            },
            AppCommand(id: "go-teams", title: "Go to Teams", symbol: "person.2", key: "2") {
                routeTo(.teams)
                commands.palettePresented = false
            },
            AppCommand(id: "go-pending", title: "Go to Pending", symbol: "clock", key: "3") {
                showPending = true
                pendingVM?.refresh()
                commands.palettePresented = false
            },
            AppCommand(id: "open-route-picker", title: "Choose model or team", symbol: "slider.horizontal.3", key: "/") {
                commands.openRoutePickerTick += 1
                commands.palettePresented = false
            },
            AppCommand(id: "focus-search", title: "Search conversations", symbol: "magnifyingglass", key: "f") {
                commands.focusSearchTick += 1
                commands.palettePresented = false
            },
            AppCommand(id: "rename-thread", title: "Rename thread", symbol: "pencil",
                       key: KeyEquivalent(Character(UnicodeScalar(0xF705)!)), modifiers: []) {
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
    /// Extracted from `workspaceContent`'s `if/else` chain — one more `HomeView` init
    /// parameter (`relayLaunchRequest`, R-S08) tipped that expression over the
    /// type-checker's complexity budget ("unable to type-check in reasonable time").
    /// Splitting the construction into its own typed property gives it a much smaller
    /// expression to solve.
    private var homeViewContent: some View {
        HomeView(
            floorRun: $floorRun,
            onAskAnotherTeam: { synthesis, team in
                threads.pendingComposerContext = .init(
                    id: UUID(), label: "Synthesis from \(team)", text: synthesis)
                routeTo(.teams)   // open the Send-to-Team launcher
            },
            onContinueWithAuto: { synthesis, team in
                threads.pendingComposerContext = .init(
                    id: UUID(), label: "Synthesis from \(team)", text: synthesis)
                floorRun = nil    // back to the current thread's composer
            },
            onOpenDevRoutes: {
                #if DEBUG
                showDevSettings = true
                #endif
            },
            onOpenCLISetup: { openCLISetup(focus: $0) },
            relayLaunchRequest: $relayLaunchRequest
        )
    }

    /// Split so Release WMO can type-check. One VStack + overlays + lifecycle
    /// chain timed out the compiler (`unable to type-check this expression`).
    private var workspaceContent: some View {
        workspaceLifecycle
    }

    private var workspaceTitleBar: some View {
        TitleBar(
            showTeamDropdown: $showTeamDropdown,
            showDoctor: $showDoctor,
            workspaceMode: $workspaceMode,
            onRoute: routeTo,
            pendingCount: pendingVM?.totalPending ?? 0,
            onRepair: openReadiness(focus:),
            onManageTeam: { openTeamStudio() },
            onOpenPending: { showPending = true },
            onOpenAbout: { openTeamStudio(route: .about) },
            onOpenPlan: { openTeamStudio(route: .plan) },
            onKeepGoing: { entitlement.presentKeepGoing() },
            devSimActive: devSimLabel,
            onSettings: openSettings
        )
        .zIndex(10)
        .onAppear {
            if pendingVM == nil { pendingVM = PendingViewModel(service: pendingService) }
            releaseUpdates.refresh()
            threads.onEntitlementLimited = { entitlement.presentKeepGoing() }
        }
        .task {
            await entitlement.refresh()
        }
    }

    @ViewBuilder
    private var workspacePane: some View {
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
                startNewTeam: studioStartNewTeam,
                cliFocusDriverId: studioCLIFocusDriverId,
                onDone: {
                    showTeamStudio = false
                    studioCustomizeTeamId = nil
                    studioStartNewTeam = false
                    studioCLIFocusDriverId = nil
                }
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
            TeamsLauncherView(
                onContinue: { workspaceMode = .inbox },
                onAddTeam: { workspaceMode = .inbox; openTeamStudio(route: .teams(.code), newTeam: true) }
            )
        } else {
            homeViewContent
        }
    }

    private var workspaceStack: some View {
        VStack(spacing: 0) {
            workspaceTitleBar
            ZStack {
                workspacePane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .textSelection(.enabled)
                if showTeamDropdown || showDoctor {
                    ALColor.scrimSubtle
                        .onTapGesture {
                            showTeamDropdown = false
                            showDoctor = false
                        }
                }
                if entitlement.showKeepGoingSheet {
                    ALColor.scrimSubtle
                        .onTapGesture { entitlement.showKeepGoingSheet = false }
                    KeepGoingSheet(model: entitlement)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .environment(threads)
        .environment(commands)
        .environment(relayResume)
        .environment(relayStop)
        .focusedSceneValue(\.appCommands, appCommands)
    }

    private var workspaceChrome: some View {
        workspaceStack
            .overlay {
                if commands.palettePresented {
                    CommandPalette(commands: appCommands) { commands.palettePresented = false }
                        .zIndex(50)
                }
            }
            .background(ALColor.base)
            .overlayPreferenceValue(TeamPillFrameKey.self) { pillFrame in
                teamDropdownOverlay(pillFrame: pillFrame)
            }
            .overlayPreferenceValue(BenchHealthFrameKey.self) { badgeFrame in
                doctorPopoverOverlay(badgeFrame: badgeFrame)
            }
    }

    @ViewBuilder
    private func teamDropdownOverlay(pillFrame: CGRect) -> some View {
        GeometryReader { geo in
            if showTeamDropdown, pillFrame != .zero {
                let origin = geo.frame(in: .global).origin
                BenchDropdownPanel(
                    isOpen: $showTeamDropdown,
                    attached: true,
                    onRepair: openReadiness(focus:),
                    onManageTeam: { openTeamStudio() },
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

    @ViewBuilder
    private func doctorPopoverOverlay(badgeFrame: CGRect) -> some View {
        GeometryReader { geo in
            if showDoctor, badgeFrame != .zero {
                let origin = geo.frame(in: .global).origin
                let top = badgeFrame.maxY - origin.y - 1
                let maxBody = max(160, geo.size.height - top - 190)
                BenchHealthPopover(
                    onClose: { showDoctor = false },
                    onOpenFull: { openCLISetup() },
                    onSelectCLI: { openCLISetup(focus: $0) },
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

    private var workspaceLifecycle: some View {
        workspaceChrome
            .onChange(of: commands.customizeTeamRequest) { _, req in
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
            .onReceive(NotificationCenter.default.publisher(for: .allnighterOpenAboutUpdates)) { _ in
                openTeamStudio(route: .about)
            }
            .onAppear(perform: handleWorkspaceAppear)
            .onChange(of: remoteAccount.pendingPairingRequests) { _, requests in
                pairingPromptRequest = requests.first
            }
            .sheet(item: $pairingPromptRequest) { request in
                RemotePairingPromptSheet(request: request)
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

    private func handleWorkspaceAppear() {
        GlobalHotKey.enable()
        #if DEBUG
        if GUIFixture.isActive {
            if GUIFixture.opensTeamDropdown { showTeamDropdown = true }
            if GUIFixture.opensDoctorPopover { showDoctor = true }
            if GUIFixture.opensReadiness {
                showReadiness = true
                readinessFocus = GUIFixture.readinessFocusDriverId
            }
            if GUIFixture.opensComposeSpecimen { showComposeSpecimen = true }
            if GUIFixture.opensTeamStudio {
                model.applyDevBenchScenario(GUIFixture.active == "studio-clis" ? "readiness-mixed" : "team-open-ready")
                GUIFixture.seedBoostWindowForProof()
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
            if GUIFixture.opensProjectsRail || GUIFixture.opensRelayLaunch {
                projects.seedForProof(ProjectsViewModel.sampleProjects(), active: "prj_halo")
                threads.currentProjectId = "prj_halo"
            }
            if GUIFixture.opensRelayLaunch {
                relayLaunchRequest = RelayLaunchRequest(
                    projectId: "prj_halo",
                    kickoffMessage: GUIFixture.relayLaunchKickoffMessage ?? ""
                )
            }
            if GUIFixture.opensKeepGoingSheet {
                entitlement.showKeepGoingSheet = true
            }
            GUIFixture.captureAndExitIfRequested()
            return
        }
        #endif
        if model.isConfigurationBroken {
            showMissingDriversAlert = true
        } else if !didLoadCachedSetup {
            didLoadCachedSetup = true
            model.loadCachedSetupState()
        }
        threads.currentProjectId = projects.activeProjectId
    }

    #if DEBUG
    private var devSimLabel: String? { devBenchScenario == nil ? nil : "sim" }

    /// The Settings gear opens the real Settings shell (CLIs · Teams) in every
    /// build. The developer GUI-routes sheet moved to a DEBUG-only sidebar-footer link
    /// (HomeSidebar.devRoutesEntry → onOpenDevRoutes), so it no longer hijacks the gear.
    private func openSettings() {
        openTeamStudio()
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

    private func openTeamStudio(route: StudioRoute = .teams(.code), newTeam: Bool = false) {
        showTeamDropdown = false
        showDoctor = false
        showReadiness = false
        studioCLIFocusDriverId = nil
        studioInitialRoute = route
        studioStartNewTeam = newTeam
        showTeamStudio = true
    }

    /// Settings shell → CLIs page. Optional focus selects that driver in the repair panel.
    /// Opening CLIs is navigation — not a detect ceremony. Only re-probe seats that still
    /// need healing; a green CLI must stay green when you tap it.
    private func openCLISetup(focus driverId: String? = nil) {
        showTeamDropdown = false
        showDoctor = false
        showReadiness = false
        studioCustomizeTeamId = nil
        studioStartNewTeam = false
        studioCLIFocusDriverId = driverId
        studioInitialRoute = .clis
        showTeamStudio = true
        if let driverId {
            let state = model.setupCards.first { $0.driverId == driverId }?.state
            if CLISetupGrouping.needsHealingProbe(state: state, includeCatalogAbsence: true) {
                model.runSetupProbe(userInitiated: true, onlyDriverId: driverId)
            }
        } else if model.setupCards.contains(where: {
            CLISetupGrouping.needsHealingProbe(state: $0.state, includeCatalogAbsence: false)
        }) {
            model.runFullSetupProbe(userInitiated: true)
        }
    }

    /// Top-bar Inbox/Teams are ROUTE COMMANDS, not passive tab labels: they dismiss every
    /// deep surface above the workspace (Factory Floor, Settings/Team Studio, Pending,
    /// Readiness, doctor + dropdown overlays) and then show the chosen route — even when
    /// that route is already selected (the Floor case). Navigation/state reset only; thread
    /// selection, run truth, and rendering are untouched.
    private func routeTo(_ mode: WorkspaceMode) {
        let next = RootRouteState(
            workspaceMode: workspaceMode, floorOpen: floorRun != nil,
            showPending: showPending, showTeamStudio: showTeamStudio,
            showReadiness: showReadiness, showDoctor: showDoctor, showTeamDropdown: showTeamDropdown
        ).routed(to: mode)
        workspaceMode = next.workspaceMode
        if !next.floorOpen { floorRun = nil }
        showPending = next.showPending
        showTeamStudio = next.showTeamStudio
        showReadiness = next.showReadiness
        showDoctor = next.showDoctor
        showTeamDropdown = next.showTeamDropdown
        studioCustomizeTeamId = nil
        studioStartNewTeam = false
        pendingVM?.refresh()
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
