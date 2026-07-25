import SwiftUI
import AppKit
import AllnighterCore
import AgentOSTeam
import AllnighterEngine

// MARK: - Factory Floor reader (docs/phases/wiring/design_handoff_team_reader)

/// The screen a user lands on after a Send-to-team run completes — reading-first:
/// the agent's reply is the hero, a left cast rail switches between each member's
/// full reply, and the markdown is rendered faithfully (our AllnighterMarkdown
/// engine) with a Rendered / Raw honesty toggle. The Lead's reply carries the one
/// piece of Allnighter chrome: the NextMove block.
/// Action to open the full Factory Floor reader for a terminal team run (the result
/// reader; the thread keeps only a compact receipt — Live_Team_Board / perf doc).
struct OpenFloorAction: @unchecked Sendable {
    let action: (TeamRun) -> Void
    func callAsFunction(_ run: TeamRun) { action(run) }
}

private struct OpenFloorKey: EnvironmentKey {
    static let defaultValue = OpenFloorAction { _ in }
}

extension EnvironmentValues {
    var openFloor: OpenFloorAction {
        get { self[OpenFloorKey.self] }
        set { self[OpenFloorKey.self] = newValue }
    }
}

struct FactoryFloorView: View {
    let run: TeamRun
    var onBack: () -> Void = {}
    /// Next-move handoffs (bug #4): open a composer with the synthesis attached. Args are
    /// (synthesis markdown, source team name).
    var onAskAnotherTeam: (String, String) -> Void = { _, _ in }
    var onContinueWithAuto: (String, String) -> Void = { _, _ in }

    @State private var selectedMemberId: String?
    @State private var rawMode = false
    @State private var promptExpanded = false
    /// Brief "Copied" flash after an auto-copy drag-select in raw mode.
    @State private var copiedFlash = false

    private var cast: [FloorCastMember] { FloorCastMember.cast(from: run) }
    private var selected: FloorCastMember? {
        cast.first { $0.id == selectedMemberId } ?? cast.first
    }
    private var floor: FloorRun { FloorProjector.project(run) }
    private var runDirectory: URL? { try? RunStore().runDirectory(forRunId: run.id) }
    private var isDesignRun: Bool { run.lane == .design || run.outputKind == .designBoard }

    var body: some View {
        HStack(spacing: 0) {
            castRail
            readerColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        // ⌥⌘R toggles raw/rich here too (same gesture as the thread). Zero-size button to
        // own the shortcut.
        .background {
            Button("") { rawMode.toggle() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .opacity(0).accessibilityHidden(true)
        }
        .overlay(alignment: .bottom) {
            if copiedFlash {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                    Text("Copied").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(ALPalette.green500)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(ALColor.raised, in: Capsule())
                .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                .padding(.bottom, 22)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: copiedFlash)
    }

    private func flashCopied() {
        copiedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedFlash = false }
    }

    private var boardChosenWorkerId: String? {
        run.latestStage(.board)?.payload?.board?.chosen?.workerId
    }

    private func designOption(for workerId: String) -> DesignOption? {
        run.latestStage(.board)?.payload?.board?.options.first { $0.workerId == workerId }
    }

    // MARK: Cast rail

    private var castRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconButton(systemImage: "chevron.left", accessibilityLabel: "Back", small: true, action: onBack)
                    Text("INBOX · RESULT").font(ALFont.monoSm.weight(.semibold)).tracking(0.8)
                        .foregroundStyle(ALColor.textFaint)
                }
                teamPill
                if ArtifactProjector.canProject(run) {
                    openArtifactButton
                }
                Divider().overlay(ALColor.borderSubtle)
                HStack {
                    Text("THE TEAM").font(ALFont.monoSm.weight(.semibold)).tracking(0.8).foregroundStyle(ALColor.textFaint)
                    Spacer()
                    Text("\(cast.count) replies").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                }
                ForEach(cast) { member in
                    CastCard(member: member, selected: selected?.id == member.id) {
                        selectedMemberId = member.id
                        // Raw stays sticky across members (founder: "one raw for everything").
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 298)
        .frame(maxHeight: .infinity)
        .background(ALColor.subtle)
        .overlay(alignment: .trailing) { Rectangle().fill(ALColor.borderSubtle).frame(width: 1) }
    }

    private var teamPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 13)).foregroundStyle(ALColor.textFaint)
            Text("\((run.lane?.rawValue ?? "team").capitalized) · ").font(ALFont.monoSm).foregroundStyle(ALColor.textMuted)
            + Text(run.teamDisplayName ?? run.presetId ?? "Team").font(ALFont.monoSm.weight(.semibold)).foregroundStyle(ALColor.textPrimary)
        }
        .lineLimit(1)
        .padding(.horizontal, 12).frame(height: 38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
    }

    private var openArtifactButton: some View {
        Button {
            ArtifactFloorOpener.openArtifact(for: run)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext").font(.system(size: 12)).foregroundStyle(ALColor.textMuted)
                Text("Open artifact").font(ALFont.monoSm.weight(.semibold)).foregroundStyle(ALColor.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("Regenerate and open the polished HTML team artifact in your browser")
    }

    // MARK: Reader column

    private var readerColumn: some View {
        VStack(spacing: 0) {
            promptBar
            readerHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let member = selected {
                        if let cause = member.failureCause {
                            // Honest failure cause (#8) — distinct from a generic timeout; a
                            // preserved partial answer (if any) still renders below.
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(ALPalette.red400)
                                Text(cause).font(.system(size: 12.5, weight: .medium)).foregroundStyle(ALPalette.red400)
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ALPalette.red400.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if isDesignRun, !member.isLead, let option = designOption(for: member.id) {
                            DesignMockupTile(
                                persona: option.persona,
                                imagePath: option.imagePath.flatMap { runDirectory?.appendingPathComponent($0).path },
                                absolutePath: option.imagePath.flatMap { rel in
                                    runDirectory.flatMap { RunImagePathResolver.absolutePath(runDirectory: $0, relativePath: rel) }
                                },
                                isChosen: boardChosenWorkerId == option.workerId,
                                failed: !option.hasImage,
                                failureReason: option.failureReason,
                                size: CGSize(width: 220, height: 320),
                                onOpen: nil
                            )
                        }
                        if rawMode {
                            // Native selectable raw source — drag-select across the whole
                            // answer (paragraphs/headings/code), auto-copy on drag-select.
                            SelectableText(text: member.markdown, onCopied: { _ in flashCopied() })
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .background(ALColor.surface, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
                        } else if !(isDesignRun && !member.isLead && designOption(for: member.id)?.hasImage == true) {
                            MarkdownText(markdown: member.markdown)
                        }
                        // Copy button at the BOTTOM of every worker answer (bug #6).
                        FloorAnswerCopyFooter(text: member.markdown)
                        if member.isLead, !rawMode { nextMove }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32).padding(.top, 18).padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptBar: some View {
        Button { promptExpanded.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("JD").font(ALFont.monoSm.weight(.semibold)).foregroundStyle(ALColor.textSecondary)
                    .frame(width: 26, height: 26).background(ALColor.surface, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOU SENT · \(cast.count) WORKERS").font(ALFont.monoSm.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(ALColor.textFaint)
                    Text(run.prompt).font(.system(size: 14)).foregroundStyle(ALColor.textSecondary)
                        .lineLimit(promptExpanded ? nil : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
                    .rotationEffect(.degrees(promptExpanded ? 180 : 0))
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private var readerHeader: some View {
        HStack(spacing: 12) {
            if let member = selected {
                Group {
                    if let driverId = member.driverId {
                        DriverBrandGlyph(driverId: driverId, boxSize: 34, iconSize: 18, cornerRadius: 9)
                    } else {
                        Image(systemName: "cpu").frame(width: 34, height: 34).background(ALColor.surface, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(member.role).font(.system(size: 15, weight: .bold)).foregroundStyle(ALColor.textPrimary)
                        if member.isLead {
                            Text("SYNTHESIS").font(.system(size: 8.5, weight: .semibold)).tracking(0.6)
                                .foregroundStyle(ALColor.accentText)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ALColor.accentBorder, lineWidth: 1))
                        }
                        WorkerStateBadge(member: member)
                    }
                    Text(member.subtitle).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                }
            }
            Spacer()
            segmentedRawToggle
            IconButton(systemImage: "doc.on.doc", accessibilityLabel: "Copy reply", small: true) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(selected?.markdown ?? "", forType: .string)
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private var segmentedRawToggle: some View {
        HStack(spacing: 2) {
            ForEach([("Rendered", false), ("Raw", true)], id: \.0) { label, raw in
                Button { rawMode = raw } label: {
                    Text(label).font(ALFont.monoSm.weight(.semibold))
                        .foregroundStyle(rawMode == raw ? ALColor.textPrimary : ALColor.textMuted)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(rawMode == raw ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
    }

    // MARK: NextMove (Allnighter chrome — Lead only)

    /// Exactly two composer-opening next moves (bug #4): hand the synthesis to a NEW team,
    /// or continue here with Auto. No Save-to-Pending / Draft / Run-when-ready — those were
    /// destination labels, not actions. Both open a composer with the synthesis attached.
    private var nextMove: some View {
        let synthesis = run.plan ?? cast.first(where: \.isLead)?.markdown ?? ""
        let teamName = run.teamDisplayName ?? run.presetId ?? "this team"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("TAKE THE NEXT MOVE", systemImage: "arrow.triangle.merge")
                    .font(ALFont.monoSm.weight(.semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                Spacer()
                Text("attaches the synthesis from \(teamName)").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            ForEach(FloorNextMovePresenter.cardMoves, id: \.kind) { move in
                nextMoveRow(label: move.label, icon: move.icon, primary: move.primary) {
                    switch move.kind {
                    case .askAnotherTeam: onAskAnotherTeam(synthesis, teamName)
                    case .continueWithAuto: onContinueWithAuto(synthesis, teamName)
                    default: break
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
        .markdownTopGap()
    }

    private func nextMoveRow(label: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(primary ? ALColor.textOnAmber : ALColor.textMuted)
                Text(label).font(.system(size: 13, weight: primary ? .semibold : .regular))
                    .foregroundStyle(primary ? ALColor.textOnAmber : ALColor.textSecondary)
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(primary ? ALColor.textOnAmber : ALColor.textFaint)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(primary ? ALColor.accent : ALColor.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(primary ? Color.clear : ALColor.borderDefault, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cast member

struct FloorCastMember: Identifiable {
    let id: String
    let role: String
    let isLead: Bool
    let modelName: String
    let driverId: String?
    let gist: String
    let markdown: String
    let status: String
    let startedAt: Date?
    let finishedAt: Date?
    let durationMs: Int?
    /// The model the team asked for, when a different ready model was substituted (#7).
    let substitutedFrom: String?
    /// An honest failure cause for a failed/timed-out worker (#8) — nil when it succeeded.
    let failureCause: String?

    var subtitle: String {
        let base = isLead ? "\(modelName) — designated lead, synthesized the team" : "\(modelName) — read the full reply below"
        if let substitutedFrom { return "\(modelName) · substituted from \(substitutedFrom)" }
        return base
    }

    /// Build the cast from a TeamRun: the plan-writer worker is the Lead (its reply
    /// is the synthesis); every other worker is a member with its raw output.
    static func cast(from run: TeamRun) -> [FloorCastMember] {
        let lead = run.workers.first { $0.purpose == .plan }
        var members: [FloorCastMember] = []
        if let lead {
            let leadAnswer = run.workerAnswer(workerId: lead.id)
            members.append(FloorCastMember(
                id: lead.id, role: title(lead.skillName, lead.skillId, fallback: "Lead"), isLead: true,
                modelName: modelName(lead.modelId), driverId: driverId(lead.modelId),
                gist: "The synthesis", markdown: run.plan ?? "(no synthesis written)",
                status: (leadAnswer?.result.status ?? .done).rawValue,
                startedAt: leadAnswer?.result.timing.startedAt, finishedAt: leadAnswer?.result.timing.finishedAt,
                durationMs: leadAnswer?.result.timing.durationMs,
                substitutedFrom: lead.substitutedFromModelId.map(modelName),
                failureCause: failureCause(leadAnswer)))
        }
        for worker in run.workers where worker.purpose != .plan {
            let answer = run.workerAnswer(workerId: worker.id)
            members.append(FloorCastMember(
                id: worker.id, role: title(worker.skillName, worker.skillId, fallback: "Worker"), isLead: false,
                modelName: modelName(worker.modelId), driverId: driverId(worker.modelId),
                gist: previewLine(answer?.output ?? ""),
                markdown: answer?.output ?? "(no reply)", status: (answer?.result.status ?? .queued).rawValue,
                startedAt: answer?.result.timing.startedAt, finishedAt: answer?.result.timing.finishedAt,
                durationMs: answer?.result.timing.durationMs,
                substitutedFrom: worker.substitutedFromModelId.map(modelName),
                failureCause: failureCause(answer)))
        }
        return members
    }

    private static func failureCause(_ answer: TeamAnswer?) -> String? {
        guard let answer else { return nil }
        return WorkerFailurePresenter.cause(
            status: answer.result.status, errorKind: answer.result.errorKind,
            errorReason: answer.result.errorReason, capacity: answer.result.capacityObservation)
    }

    /// The worker's job title: the skill display name, else a humanized skill id, else a
    /// generic fallback — never a raw `model_x#0` worker id.
    private static func title(_ skillName: String?, _ skillId: String?, fallback: String) -> String {
        if let skillName, !skillName.isEmpty { return skillName }
        if let skillId, !skillId.isEmpty {
            return skillId.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        return fallback
    }

    private static func modelName(_ modelId: String) -> String {
        ModelCatalog.get(modelId)?.displayName ?? modelId
    }
    /// The vendor/driver id for the brand glyph (model → driver), not the model id.
    private static func driverId(_ modelId: String) -> String? {
        ModelCatalog.get(modelId)?.driverId
    }

    /// A clean one-line plain-text preview for the cast rail — strips leading
    /// Markdown markers (heading `#`, list bullets, blockquote `>`, emphasis `*`/`_`)
    /// so the sidebar never leaks raw syntax like "## 12 public posts…".
    private static func previewLine(_ markdown: String) -> String {
        let firstContent = markdown
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let stripped = firstContent.drop { "#>-*_• ".contains($0) }
        return String(stripped.replacingOccurrences(of: "*", with: "").prefix(60))
    }
}

private struct CastCard: View {
    let member: FloorCastMember
    let selected: Bool
    var onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 11) {
                Group {
                    if let driverId = member.driverId {
                        DriverBrandGlyph(driverId: driverId, boxSize: 32, iconSize: 17, cornerRadius: 9, muted: !selected)
                    } else {
                        Image(systemName: "cpu").frame(width: 32, height: 32).background(ALColor.surface, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        // Worker JOB/TITLE first (bug #1).
                        Text(member.role).font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                        if member.isLead {
                            Text("synthesis").font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(ALColor.accentText)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ALColor.accentBorder, lineWidth: 1))
                        }
                        Spacer(minLength: 4)
                        WorkerStateBadge(member: member)
                    }
                    HStack(spacing: 4) {
                        Text(member.modelName).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint).lineLimit(1)
                        if let from = member.substitutedFrom {
                            Text("· from \(from)").font(.system(size: 9, weight: .medium))
                                .foregroundStyle(ALColor.accentText).lineLimit(1)
                                .help("Substituted from \(from) (preferred model unavailable)")
                        }
                    }
                    if let cause = member.failureCause {
                        Text(cause).font(.system(size: 11)).foregroundStyle(ALPalette.red400).lineLimit(1)
                    } else {
                        Text(member.gist).font(.system(size: 11.5)).foregroundStyle(ALColor.textFaint).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Hover affordance (#3): a quiet hover surface, distinct from the brighter
            // selected surface; selected+hover stays legible.
            .background(selected ? ALColor.active : (hovering ? ALColor.hover : Color.clear),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) {
                if selected && member.isLead { Rectangle().fill(ALColor.accent).frame(width: 2) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Copy footer below a Floor worker answer (bug #6) — copies the exact response body.
private struct FloorAnswerCopyFooter: View {
    let text: String
    @State private var copied = false

    var body: some View {
        if !text.isEmpty {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .medium))
                        Text(copied ? "Copied" : "Copy").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(copied ? ALPalette.green500 : ALColor.textMuted)
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(ALColor.subtle, in: Capsule())
                    .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .help("Copy this worker's answer")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A worker's live/terminal state dot + response time (#2). Running workers tick.
private struct WorkerStateBadge: View {
    let member: FloorCastMember

    var body: some View {
        let dot = FloorWorkerStatePresenter.dot(status: member.status)
        if dot == .running {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                badge(dot: dot, label: durationLabel(now: ctx.date))
            }
        } else {
            badge(dot: dot, label: durationLabel(now: Date()))
        }
    }

    private func durationLabel(now: Date) -> String? {
        FloorWorkerStatePresenter.durationLabel(
            status: member.status, startedAt: member.startedAt,
            finishedAt: member.finishedAt, durationMs: member.durationMs, now: now)
    }

    private func badge(dot: FloorWorkerStatePresenter.Dot, label: String?) -> some View {
        HStack(spacing: 4) {
            if let label {
                Text(label).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(ALColor.textFaint)
            }
            Circle().fill(dot.color).frame(width: 6, height: 6)
        }
    }
}

private extension View {
    /// Small top margin so the NextMove card doesn't hug the reply text.
    func markdownTopGap() -> some View { padding(.top, 8) }
}

