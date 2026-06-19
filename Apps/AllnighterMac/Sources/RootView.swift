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
            AppCommand(id: "new-run", title: "New run", symbol: "plus", key: "n") {
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
                    if showFloorReaderProof {
                        floorReaderProofView
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
                        ComposeSpecimen(openTarget: GUIFixture.composeTargetOpen)
                    } else if workspaceMode == .teams {
                        // Teams workspace — the Send-to-team launcher (G-T1 brings
                        // full fidelity; G-T0 wires the toggle + a real card roster).
                        TeamsLauncherView(onContinue: { workspaceMode = .inbox })
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

// MARK: - Title bar (chrome.jsx .alk-title)

private struct TitleBar: View {
    @Binding var showTeamDropdown: Bool
    @Binding var showDoctor: Bool
    @Binding var workspaceMode: WorkspaceMode
    /// Inbox unread badge count. Real unread truth wires with the Projects sidebar
    /// (G-T4); 0 until then (no fabricated count).
    var unread: Int = 0
    var onRepair: (String) -> Void
    var onManageTeam: () -> Void
    var devSimActive: String?
    var onSettings: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            // Leading inset clears the macOS traffic-light controls (hidden title
            // bar overlays them at the top-left) so the toggle never collides.
            Spacer().frame(width: ALControl.trafficLightInset)
            // Left: live mark + the Inbox | Teams workspace switch.
            LiveMark(state: model.isRunning ? .running : .idle, size: 16)
            InboxTeamsSwitch(mode: $workspaceMode, unread: unread)
            if let devSimActive {
                Badge(text: devSimActive, tone: .warning, dot: true, mono: true)
            }
            Spacer()
            // Right controls
            HStack(spacing: 6) {
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

// MARK: - Workspace switcher (Council ↔ Threads)

/// The two top-level workspaces (Send-to-team handoff §Global shell). `inbox` is
/// today's chat/conversation home; `teams` is the Send-to-team launcher.
enum WorkspaceMode: String, CaseIterable {
    case inbox, teams

    var label: String { self == .inbox ? "Inbox" : "Teams" }
    /// SF Symbol — Lucide `inbox`→`tray`, `users-round`→`person.2`.
    var symbol: String { self == .inbox ? "tray" : "person.2" }
}

/// `Inbox | Teams` segmented top-bar control (handoff `.modeswitch`). Active
/// segment: `bgActive` fill + inset hairline + `ink50` text; inactive: `textMuted`.
/// Inbox carries an unread badge.
struct InboxTeamsSwitch: View {
    @Binding var mode: WorkspaceMode
    var unread: Int = 0

    var body: some View {
        HStack(spacing: 3) {
            segment(.inbox)
            segment(.teams)
        }
        .padding(3)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay(RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private func segment(_ item: WorkspaceMode) -> some View {
        let isActive = mode == item
        Button { mode = item } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol).font(.system(size: 12, weight: .medium))
                Text(item.label).font(ALFont.label.weight(.semibold))
                if item == .inbox, unread > 0 {
                    Text("\(unread)")
                        .font(ALFont.monoSm.weight(.semibold))
                        .foregroundStyle(ALColor.accentText)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(ALColor.accentSurface, in: Capsule())
                }
            }
            .foregroundStyle(isActive ? ALColor.textPrimary : ALColor.textMuted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(segmentBackground(isActive))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(item.label) (\u{2318}\(item == .inbox ? "1" : "2"))")
    }

    @ViewBuilder
    private func segmentBackground(_ isActive: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: ALRadius.sm)
                .fill(ALColor.active)
                .overlay(RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
        }
    }
}
