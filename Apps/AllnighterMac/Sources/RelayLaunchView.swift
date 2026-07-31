import SwiftUI
import AllnighterCore
import AllnighterEngine

/// `.sheet(item:)` payload — the project a relay is being started in (HomeSidebar's
/// project-group "Start relay" affordance, mirroring the existing "New agent in project"
/// `+` button right next to it).
struct RelayLaunchRequest: Identifiable {
    let projectId: String
    var kickoffMessage: String = ""
    var id: String { projectId }
}

/// Opens the Loop launch sheet from the composer (ATL-S03).
struct OpenLoopLaunchAction: @unchecked Sendable {
    let action: (_ kickoff: String, _ projectId: String) -> Void
    func callAsFunction(kickoff: String, projectId: String) { action(kickoff, projectId) }
}

private struct OpenLoopLaunchKey: EnvironmentKey {
    static let defaultValue = OpenLoopLaunchAction { _, _ in }
}

extension EnvironmentValues {
    var openLoopLaunch: OpenLoopLaunchAction {
        get { self[OpenLoopLaunchKey.self] }
        set { self[OpenLoopLaunchKey.self] = newValue }
    }
}

/// R-S08 — the Mac GUI's PM Relay launch surface (`docs/phases/PM_Relay.md` §6, the last
/// open slice). A doc picker (ranked file search, reusing `ProjectFileCatalog` — the same
/// engine the composer's `@`-file-reference picker ranks against), a PM seat + dev seat
/// picker (the composer's own bench data, `AppModel.composeBench`), ceilings, and Start.
struct RelayLaunchView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(ProjectsViewModel.self) private var projects
    @Environment(\.dismiss) private var dismiss

    let request: RelayLaunchRequest

    @State private var viewModel: RelayLaunchViewModel?
    @State private var docQuery = ""
    @State private var docCandidates: [ProjectFileCatalog.Candidate] = []
    @State private var docSnapshot: ProjectFileCatalog.Snapshot?

    private var readySeats: [ComposeBenchModel] { appModel.composeBench.filter(\.ready) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            if let viewModel {
                // `.safeAreaInset` (not a sibling-below layout, and never an `.overlay`) is
                // the structural fix for the sticky footer: it reserves the footer's actual
                // rendered height as bottom inset on the scroll content automatically, so the
                // last row can never sit flush against — let alone under — the footer, at any
                // scroll position or content length. No magic-number padding to keep in sync.
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        kickoffSection(viewModel)
                        docSection(viewModel)
                        seatSection(
                            title: "PM seat", subtitle: "Reviews rounds, writes the handover.",
                            selected: Binding(get: { viewModel.pmModelId }, set: { viewModel.pmModelId = $0 })
                        )
                        seatSection(
                            title: "Dev seat", subtitle: "Builds, commits, reports back.",
                            selected: Binding(get: { viewModel.devModelId }, set: { viewModel.devModelId = $0 })
                        )
                        ceilingsSection(viewModel)
                        if !viewModel.validationIssues.isEmpty || viewModel.startRefusalIssue != nil {
                            issuesBlock(viewModel)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 16)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    footer(viewModel)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // 640 was too short for its own content: with two ~168pt-tall bounded seat
        // lists plus doc/toggle/ceilings sections, the form's natural height comfortably
        // exceeds 640, so the *outer* form ScrollView's own clip edge (not the footer)
        // landed mid-row inside the Dev seat list — flush against the footer with zero
        // gap, reading as the footer overlapping the list. 680 (+ the tighter spacing
        // above) gives both seat sections room to render without the outer scroll
        // clipping into either box on first open, while staying inside the fixed
        // 1100x720 GUI-proof capture window (and the app's real 720pt minHeight) with
        // margin to spare — a taller frame (tried 740) overflowed that window's top
        // edge. The form still scrolls for ceilings/issues or an unusually deep bench
        // (9+ ready seats); each seat box scrolls independently within its own bound.
        .frame(width: 480, height: 680)
        .background(ALColor.surface)
        .task { bootstrap() }
        .task(id: docQuery) { rankDocCandidates() }
    }

    // MARK: - Setup

    private func bootstrap() {
        guard viewModel == nil else { return }
        let root = project?.normalizedRootPath ?? ""
        viewModel = RelayLaunchViewModel(
            projectId: request.projectId, projectRoot: root,
            models: appModel.models, registry: appModel.registry,
            readyModels: appModel.availableModels,
            initialKickoffMessage: request.kickoffMessage
        )
        Task.detached(priority: .userInitiated) {
            let snapshot = ProjectFileCatalog().snapshot(rootPath: root)
            await MainActor.run { docSnapshot = snapshot }
        }
    }

    private func rankDocCandidates() {
        guard let docSnapshot else { docCandidates = []; return }
        let ranked = ProjectFileCatalog().rank(docSnapshot, query: docQuery, limit: 12)
        // Doc surface only — a relay's spec doc is prose, not source; still show
        // everything if the query is too generic to have narrowed anything markdown-ish.
        let markdownFirst = ranked.filter { $0.path.hasSuffix(".md") || $0.path.hasSuffix(".markdown") }
        docCandidates = docQuery.isEmpty ? markdownFirst : ranked
    }

    // MARK: - Header / footer

    private var project: Project? { projects.projects.first { $0.id == request.projectId } }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start a loop").font(ALFont.h3).foregroundStyle(ALColor.textPrimary)
                Text(project?.displayName ?? "").font(ALFont.caption).foregroundStyle(ALColor.textFaint)
            }
            Spacer()
            IconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
        }
        .padding(16)
    }

    private func footer(_ viewModel: RelayLaunchViewModel) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            HStack {
                Text("PM ↔ dev, unattended — reviews the real commits each round.")
                    .font(ALFont.caption).foregroundStyle(ALColor.textFaint)
                Spacer()
                Button("Start loop") {
                    Task {
                        guard let loopId = await viewModel.start() else { return }
                        threads.reload()
                        threads.select(threadId: loopId)
                        threads.markLoopComposerCleared()
                        dismiss()
                    }
                }
                .buttonStyle(.alPrimary)
                .disabled(!viewModel.canStart)
            }
            .padding(16)
        }
        // Opaque: this now lives in the ScrollView's reserved `.safeAreaInset` region, so
        // scroll-bounce content must never show through underneath it.
        .background(ALColor.surface)
    }

    // MARK: - Kickoff

    private func kickoffSection(_ viewModel: RelayLaunchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Kickoff")
            Text("Brief the PM once — not a chat")
                .font(ALFont.caption).foregroundStyle(ALColor.textFaint)
            TextField("What should this loop deliver?", text: Binding(
                get: { viewModel.kickoffMessage },
                set: { viewModel.kickoffMessage = $0 }
            ))
            .textFieldStyle(.plain)
            .font(ALFont.body)
            .padding(.horizontal, 10).frame(minHeight: ALControl.height)
            .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
    }

    // MARK: - Doc section

    private func docSection(_ viewModel: RelayLaunchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Spec doc")
            TextField("docs/phases/your-spec.md", text: Binding(
                get: { viewModel.docPath },
                set: { viewModel.docPath = $0; docQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(ALFont.body)
            .padding(.horizontal, 10).frame(height: ALControl.height)
            .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            if !docCandidates.isEmpty, viewModel.docPath != docCandidates.first?.path {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(docCandidates.prefix(6), id: \.path) { candidate in
                        Button {
                            viewModel.docPath = candidate.path
                            docQuery = candidate.path
                        } label: {
                            Text(candidate.path)
                                .font(ALFont.monoSm).foregroundStyle(ALColor.textSecondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).frame(height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            }
            Text("Typed repo-relative path works too — the PM re-reads it fresh every round.")
                .font(ALFont.caption).foregroundStyle(ALColor.textFaint)
        }
    }

    // MARK: - Seat section

    private func seatSection(
        title: String, subtitle: String, selected: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            Text(subtitle).font(ALFont.caption).foregroundStyle(ALColor.textFaint)
            // Height-capped + independently scrollable: the bench can run to 9+ ready
            // seats, and two of these plus the doc/ceilings sections in one outer
            // ScrollView would bury "Dev seat" and Start behind a long scroll. Each
            // picker gets its own short, bounded viewport instead (~4 rows visible).
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(readySeats) { seat in
                        seatRow(seat, selected: selected.wrappedValue == seat.id) {
                            selected.wrappedValue = seat.id
                        }
                    }
                    if readySeats.isEmpty {
                        Text("No ready CLIs — check Setup.").font(ALFont.caption).foregroundStyle(ALColor.textFaint)
                            .padding(.vertical, 6)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 152)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            // Scroll cue: the list is intentionally height-capped to ~4.5 rows so a partial
            // row hints "more below" — but with no gradient it reads as a hard clip rather
            // than an affordance. Soft-fade the last few points to the box's own background.
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [ALColor.raised.opacity(0), ALColor.raised],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 22)
                .allowsHitTesting(false)
            }
        }
    }

    private func seatRow(
        _ seat: ComposeBenchModel, selected: Bool, onSelect: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                DriverBrandGlyph(driverId: seat.driverId, boxSize: 22, iconSize: 12, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(seat.name).font(ALFont.label).foregroundStyle(ALColor.textPrimary)
                    Text(seat.sub).font(ALFont.caption).foregroundStyle(ALColor.textFaint)
                }
                Spacer(minLength: 4)
                if selected { Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(ALColor.accentText) }
            }
            .padding(.horizontal, 8).frame(height: 36)
            .background(selected ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ceilings

    private func ceilingsSection(_ viewModel: RelayLaunchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Ceilings")
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max rounds").font(ALFont.caption).foregroundStyle(ALColor.textFaint)
                    Stepper(value: Binding(get: { viewModel.maxRounds }, set: { viewModel.maxRounds = $0 }), in: 1...200) {
                        Text("\(viewModel.maxRounds)").font(ALFont.mono).foregroundStyle(ALColor.textPrimary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Until (HH:MM, optional)").font(ALFont.caption).foregroundStyle(ALColor.textFaint)
                    TextField("07:00", text: Binding(get: { viewModel.untilTime }, set: { viewModel.untilTime = $0 }))
                        .textFieldStyle(.plain)
                        .font(ALFont.mono)
                        .padding(.horizontal, 8).frame(width: 80, height: ALControl.heightSm)
                        .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                        .overlay { RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                }
                Spacer()
            }
        }
    }

    // RSC-S02: `startRefusalIssue` is a dynamic, disk-backed fact (a duplicate-relay
    // refusal from `LoopCoordinator.preflightStart`) rather than a form-completeness
    // issue, so it is not folded into `validationIssues`/`canStart` — but it renders in
    // the same block so a refused Start click is never silent. It clears at the top of
    // every `start()` attempt, so retrying re-checks fresh.
    private func issuesBlock(_ viewModel: RelayLaunchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.validationIssues) { issue in
                issueRow(issue.message)
            }
            if let refusal = viewModel.startRefusalIssue {
                issueRow(refusal.message)
            }
        }
        .padding(10)
        .background(ALColor.warningSurface, in: RoundedRectangle(cornerRadius: ALRadius.sm))
    }

    private func issueRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(ALPalette.amber400)
            Text(message).font(ALFont.caption).foregroundStyle(ALColor.textMuted)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
            .foregroundStyle(ALColor.textFaint)
    }
}
