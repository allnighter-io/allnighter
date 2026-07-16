import SwiftUI
import AllnighterCore
import AllnighterEngine

/// `.sheet(item:)` payload — the project a relay is being started in (HomeSidebar's
/// project-group "Start relay" affordance, mirroring the existing "New agent in project"
/// `+` button right next to it).
struct RelayLaunchRequest: Identifiable {
    let projectId: String
    var id: String { projectId }
}

/// R-S08 — the Mac GUI's PM Relay launch surface (`docs/phases/PM_Relay.md` §6, the last
/// open slice). A doc picker (ranked file search, reusing `ProjectFileCatalog` — the same
/// engine the composer's `@`-file-reference picker ranks against), a PM seat + dev seat
/// picker (the composer's own bench data, `AppModel.composeBench`), `--pm-read-only` with
/// fail-closed seat annotation, ceilings, and Start.
struct RelayLaunchView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(ProjectsViewModel.self) private var projects
    @Environment(\.dismiss) private var dismiss

    let projectId: String

    @State private var viewModel: RelayLaunchViewModel?
    @State private var docQuery = ""
    @State private var docCandidates: [ProjectFileCatalog.Candidate] = []
    @State private var docSnapshot: ProjectFileCatalog.Snapshot?

    private var project: Project? { projects.projects.first { $0.id == projectId } }
    private var readySeats: [ComposeBenchModel] { appModel.composeBench.filter(\.ready) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            if let viewModel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        docSection(viewModel)
                        seatSection(
                            title: "PM seat", subtitle: "Reviews rounds, writes the handover.",
                            selected: Binding(get: { viewModel.pmWorkerId }, set: { viewModel.pmWorkerId = $0 }),
                            readOnlyGated: viewModel.pmReadOnly,
                            unsupportedReason: { viewModel.readOnlyUnsupportedReason(for: $0) }
                        )
                        readOnlyToggle(viewModel)
                        seatSection(
                            title: "Dev seat", subtitle: "Builds, commits, reports back.",
                            selected: Binding(get: { viewModel.devWorkerId }, set: { viewModel.devWorkerId = $0 }),
                            readOnlyGated: false,
                            unsupportedReason: { _ in nil }
                        )
                        ceilingsSection(viewModel)
                        if !viewModel.validationIssues.isEmpty {
                            issuesBlock(viewModel)
                        }
                    }
                    .padding(20)
                }
                footer(viewModel)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 480, height: 640)
        .background(ALColor.surface)
        .task { bootstrap() }
        .task(id: docQuery) { rankDocCandidates() }
    }

    // MARK: - Setup

    private func bootstrap() {
        guard viewModel == nil else { return }
        let root = project?.normalizedRootPath ?? ""
        viewModel = RelayLaunchViewModel(
            projectId: projectId, projectRoot: root,
            models: appModel.models, registry: appModel.registry,
            readyModels: appModel.availableModels
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start a relay").font(ALFont.h3).foregroundStyle(ALColor.textPrimary)
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
                Button("Start") {
                    guard let relayId = viewModel.start(onEvent: { _ in
                        Task { @MainActor in threads.requestReload() }
                    }) else { return }
                    threads.reload()
                    threads.select(threadId: relayId)
                    dismiss()
                }
                .buttonStyle(.alPrimary)
                .disabled(!viewModel.canStart)
            }
            .padding(16)
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
        title: String, subtitle: String, selected: Binding<String?>,
        readOnlyGated: Bool, unsupportedReason: @escaping (String) -> String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            Text(subtitle).font(ALFont.caption).foregroundStyle(ALColor.textFaint)
            // Height-capped + independently scrollable: the bench can run to 9+ ready
            // seats, and two of these plus the doc/toggle/ceilings sections in one outer
            // ScrollView would bury "Dev seat" and Start behind a long scroll. Each
            // picker gets its own short, bounded viewport instead (~4.5 rows visible).
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(readySeats) { seat in
                        let reason = readOnlyGated ? unsupportedReason(seat.id) : nil
                        seatRow(seat, selected: selected.wrappedValue == seat.id, disabledReason: reason) {
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
            .frame(maxHeight: 168)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
    }

    private func seatRow(
        _ seat: ComposeBenchModel, selected: Bool, disabledReason: String?, onSelect: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                DriverBrandGlyph(driverId: seat.driverId, boxSize: 22, iconSize: 12, cornerRadius: 6, muted: disabledReason != nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(seat.name).font(ALFont.label)
                        .foregroundStyle(disabledReason != nil ? ALColor.textFaint : ALColor.textPrimary)
                    if let disabledReason {
                        Text(disabledReason).font(.system(size: 10)).foregroundStyle(ALPalette.amber400).lineLimit(2)
                    } else {
                        Text(seat.sub).font(ALFont.caption).foregroundStyle(ALColor.textFaint)
                    }
                }
                Spacer(minLength: 4)
                if selected { Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(ALColor.accentText) }
            }
            .padding(.horizontal, 8).frame(height: 36)
            .background(selected ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabledReason != nil)
    }

    private func readOnlyToggle(_ viewModel: RelayLaunchViewModel) -> some View {
        Toggle(isOn: Binding(get: { viewModel.pmReadOnly }, set: { viewModel.pmReadOnly = $0 })) {
            VStack(alignment: .leading, spacing: 1) {
                Text("PM is mechanically read-only").font(ALFont.label).foregroundStyle(ALColor.textPrimary)
                Text("Enforced by the seat's own CLI (plan/sandbox mode) — not a prompt.")
                    .font(ALFont.caption).foregroundStyle(ALColor.textFaint)
            }
        }
        .toggleStyle(.switch)
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

    private func issuesBlock(_ viewModel: RelayLaunchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.validationIssues) { issue in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(ALPalette.amber400)
                    Text(issue.message).font(ALFont.caption).foregroundStyle(ALColor.textMuted)
                }
            }
        }
        .padding(10)
        .background(ALColor.warningSurface, in: RoundedRectangle(cornerRadius: ALRadius.sm))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
            .foregroundStyle(ALColor.textFaint)
    }
}
