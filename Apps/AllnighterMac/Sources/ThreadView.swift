import SwiftUI
import AppKit
import AllnighterCore

// Conversation thread pane (docs/phases/wiring/compose-routing, reference/app.jsx
// ThreadPane + NewPane). CR4a: userMessage turns + docked RoutingComposer; worker
// replies land in CR4b.

struct ThreadView: View {
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let thread = threads.selectedThread {
            if thread.turns.isEmpty {
                ThreadEmptyState(thread: thread)
            } else {
                ThreadConversationPane(thread: thread)
            }
        }
    }
}

// MARK: - Empty thread ("Start a run")

private struct ThreadEmptyState: View {
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(AppModel.self) private var appModel
    let thread: WorkThread

    // CLI-based readiness — same source as the title-bar badge (no header/body drift).
    private var readyCount: Int { appModel.readyToolCount }
    private var totalCount: Int { appModel.totalToolCount }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                AllnighterGlyph(size: 38)
                Text("Start a run")
                    .font(.system(size: 25, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(ALColor.textPrimary)
                Text("One message plus an optional team and worker, running in the selected repo root.")
                    .font(.system(size: 13.5)).foregroundStyle(ALColor.textMuted)
                    .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 486)
                HStack(spacing: 8) {
                    Circle().fill(readyCount > 0 ? ALPalette.green500 : ALColor.textFaint).frame(width: 6, height: 6)
                    Text(readyCount == totalCount ? "\(readyCount) CLIs ready" : "\(readyCount)/\(totalCount) CLIs ready")
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textMuted)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
            RoutingComposer(
                big: true,
                onSend: { threads.sendRouting($0) }
            )
            .frame(maxWidth: 640)
            .padding(.horizontal, 28).padding(.bottom, 28)
            .disabled(thread.isArchived)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .overlay {
            if thread.isArchived {
                archivedComposerOverlay
            }
        }
    }

    private var archivedComposerOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "archivebox").foregroundStyle(ALColor.textFaint)
                Text("Unarchive to reply").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
                Spacer()
                Button("Unarchive") { threads.unarchiveThread(thread.id) }
                    .buttonStyle(.alLight)
            }
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(ALColor.base.opacity(0.92))
        }
    }
}

// MARK: - Thread with turns

private struct ThreadConversationPane: View {
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread

    var body: some View {
        VStack(spacing: 0) {
            ThreadPaneHeader(thread: thread)
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            ThreadTurnTimeline(thread: thread)
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            if thread.isArchived {
                archivedComposerBar
            } else {
                RoutingComposer(
                    onSend: { threads.sendRouting($0) }
                )
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }

    private var archivedComposerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox").foregroundStyle(ALColor.textFaint)
            Text("Unarchive to reply")
                .font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
            Spacer()
            Button("Unarchive") { threads.unarchiveThread(thread.id) }
                .buttonStyle(.alLight)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

private struct ThreadPaneHeader: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(CommandCenter.self) private var commands
    let thread: WorkThread
    @State private var editTitle = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if thread.isArchived {
                Text(thread.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ALColor.textPrimary)
                    .lineLimit(1)
                Text("Archived")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ALColor.textMuted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(ALColor.surface, in: Capsule())
            } else {
                TextField("Title", text: $editTitle, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ALColor.textPrimary)
                    .focused($titleFocused)
            }
            if let lane = inferredLane {
                laneChip(lane)
            }
            Spacer(minLength: 8)
            if thread.isArchived {
                Button("Unarchive") { threads.unarchiveThread(thread.id) }
                    .buttonStyle(.alLight)
            } else {
                Button { threads.togglePin(for: thread) } label: {
                    Image(systemName: thread.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ALColor.textMuted)
                .help(thread.isPinned ? "Unpin" : "Pin")
                Button("Archive") { threads.archiveThread(thread.id) }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ALColor.textMuted)
                    .buttonStyle(.plain)
            }
            // Who you're talking to — the model name(s), not a CLI logo. The name is
            // what actually tells you who answered (founder: "10x more valuable").
            if !routedModelNames.isEmpty {
                let names = routedModelNames
                Text(names.prefix(2).joined(separator: " · ") + (names.count > 2 ? " +\(names.count - 2)" : ""))
                    .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint).lineLimit(1)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .onAppear { editTitle = thread.title }
        .onChange(of: thread.title) { _, title in editTitle = title }
        .onChange(of: commands.focusRenameTick) { _, _ in titleFocused = true }
    }

    private func commitRename() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        threads.renameThread(thread.id, title: trimmed)
    }

    // A normal chat/code run gets NO lane chip — it's just a conversation (founder).
    // Only the genuinely distinct Design surface (an image board) is badged.
    private var inferredLane: ComposeLane? {
        if thread.turns.contains(where: { $0.kind == .designBoard }) { return .design }
        return nil
    }

    private var routedWorkerIds: [String] {
        var seen = Set<String>()
        return thread.turns.compactMap(\.workerId).filter { seen.insert($0).inserted }
    }

    /// Distinct model display names that have answered in this thread. A worker id is
    /// `modelId#instanceIndex` (Worker.makeID), so strip the suffix before resolving.
    /// Resolve against the full model catalog (not just the live bench) so the name
    /// shows even for a model that isn't currently benched — and dedupe by name.
    private var routedModelNames: [String] {
        var seen = Set<String>()
        return routedWorkerIds.compactMap { wid -> String? in
            let modelId = wid.split(separator: "#").first.map(String.init) ?? wid
            guard let name = appModel.models.first(where: { $0.id == modelId })?.displayName else { return nil }
            return seen.insert(name).inserted ? name : nil
        }
    }

    private func laneChip(_ lane: ComposeLane) -> some View {
        HStack(spacing: 4) {
            Image(systemName: lane.icon).font(.system(size: 11))
            Text(lane.label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(lane == .design ? ALColor.accentText : ALColor.textSecondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(lane == .design ? ALColor.active : ALColor.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }
}

private struct ThreadTurnTimeline: View {
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(thread.turns) { turn in
                        ThreadTurnRow(turn: turn)
                            .id(turn.id)
                            .timelineTurnFrame(turnId: turn.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .timelineVisibilityTracking(thread: thread)
            .onAppear {
                TimelineScrollPolicy.scrollToUnreadIfNeeded(
                    proxy: proxy,
                    thread: thread,
                    pendingTarget: threads.consumePendingScrollTarget(),
                    suppressAutoScroll: GUIFixture.suppressUnreadAutoScroll
                )
            }
            .onChange(of: thread.turns.count) { _, _ in
                TimelineScrollPolicy.scrollOnTurnCountChange(
                    proxy: proxy,
                    thread: thread,
                    suppressAutoScroll: GUIFixture.suppressUnreadAutoScroll
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// CR4a user messages + CR4b worker chat replies; team/mutating run turns render
/// from durable run truth.
/// Live "thinking" surface — the model's reasoning streamed while it works, kept
/// visually distinct from (and above) the answer. Renders nothing when there's no
/// reasoning. Plain muted text in a subtle card; never the final answer.
private struct ThreadThinkingBlock: View {
    let text: String?

    var body: some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "brain").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
                    Text("Thinking").font(.system(size: 10, weight: .semibold)).tracking(0.4)
                        .foregroundStyle(ALColor.textFaint)
                }
                Text(text)
                    .font(.system(size: 12)).foregroundStyle(ALColor.textMuted)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
    }
}

private struct ThreadTurnRow: View {
    @Environment(AppModel.self) private var appModel
    let turn: ThreadTurn

    var body: some View {
        switch turn.kind {
        case .userMessage, .userDecision:
            userBubble
        case .workerChat:
            workerBubble
        case .teamRun, .designBoard, .reviewBoard:
            ThreadBoardRow(turn: turn)
        case .mutatingRun:
            ThreadMutatingRunRow(turn: turn)
        default:
            stubTurn
        }
    }

    // CR4b — one model's reply.
    private var model: ComposeBenchModel? {
        guard let id = turn.workerId else { return nil }
        return appModel.composeBench.first(where: { $0.id == id })
    }

    private var workerBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let model { DriverBrandGlyph(driverId: model.driverId, boxSize: 28, iconSize: 14, cornerRadius: 7) }
                else { Image(systemName: "cpu").font(.system(size: 13)).foregroundStyle(ALColor.textSecondary).frame(width: 28, height: 28).background(ALColor.subtle, in: RoundedRectangle(cornerRadius: 7)) }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(model?.name ?? turn.workerId ?? "Model")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ALColor.textSecondary)
                    Text(turn.createdAt, format: .dateTime.hour().minute())
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                }
                switch turn.status {
                case .running, .queued, .draft:
                    VStack(alignment: .leading, spacing: 8) {
                        // Live "thinking" — the model's reasoning while it works.
                        ThreadThinkingBlock(text: turn.reasoningText)
                        if let partial = turn.text, !partial.isEmpty {
                            // Live streaming text — PLAIN while running so malformed
                            // in-progress Markdown can't break layout; the settled .done
                            // state re-renders through the Markdown engine.
                            VStack(alignment: .leading, spacing: 4) {
                                Text(partial)
                                    .font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(turn.partialOutputTruncated ? "streaming… (truncated)" : "streaming…")
                                        .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                                }
                            }
                        } else {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(turn.reasoningText?.isEmpty == false ? "thinking…" : "running…")
                                    .font(.system(size: 12)).foregroundStyle(ALColor.textMuted)
                            }
                        }
                    }
                case .failed, .timedOut:
                    Text(turn.text?.isEmpty == false ? (turn.text ?? "") : "The worker failed.")
                        .font(.system(size: 13))
                        .foregroundStyle(ALPalette.red400)
                        .textSelection(.enabled)
                case .cancelled:
                    Text("Cancelled.").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
                case .done:
                    // Agent replies render through our markdown engine (block-level:
                    // headings/lists/code/quotes/tables), not inline-only Text.
                    MarkdownText(markdown: turn.text ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var userBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("YOU")
                .font(.system(size: 9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(ALColor.textFaint)
                .frame(width: 28, height: 28)
                .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("You")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ALColor.textSecondary)
                    Text(turn.createdAt, format: .dateTime.hour().minute())
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                }
                Text(turn.text ?? "")
                    .font(.system(size: 13.5))
                    .foregroundStyle(ALColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                    .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    private var stubTurn: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis.circle").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
            Text(turn.kind.rawValue.replacingOccurrences(of: "_", with: " "))
                .font(ALFont.caption).foregroundStyle(ALColor.textMuted)
            StatusPill(kind: ThreadsPresenter.pillKind(for: turn.status))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - CR4c team board

/// A team run result: the team's synthesis up top, then each model's answer as a
/// card. Renders from the durable TeamRun behind the turn's `runId` (turn → run →
/// answers + plan), so it always shows the real path — never a faked board.
private struct ThreadBoardRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    let turn: ThreadTurn

    private var run: TeamRun? { turn.runId.flatMap { threads.teamRun(forRunId: $0) } }
    private var synthesis: String? {
        run?.stages.last { $0.purpose == .plan && $0.status == .done }?.payload?.markdown
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: turn.kind == .designBoard ? "paintbrush.fill" : "person.3.sequence.fill")
                .font(.system(size: 13)).foregroundStyle(ALColor.accent)
                .frame(width: 28, height: 28)
                .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 8) {
                header
                content
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(turn.kind == .designBoard ? "Design board" : "Team board")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(ALColor.textSecondary)
            if let n = run?.workerAnswers.count, n > 0 {
                Text("· \(n) models").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            Text(turn.createdAt, format: .dateTime.hour().minute())
                .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
        }
    }

    @ViewBuilder private var content: some View {
        switch turn.status {
        case .running, .queued, .draft:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("fanning out…").font(.system(size: 12)).foregroundStyle(ALColor.textMuted)
            }
        case .cancelled:
            Text("Cancelled.").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
        case .failed, .timedOut:
            // A team that couldn't resolve/run has no board — show the honest
            // reason. A run that produced answers but ended partial still shows them.
            if run == nil {
                Text(turn.text?.isEmpty == false ? (turn.text ?? "") : "The team couldn't run.")
                    .font(.system(size: 13)).foregroundStyle(ALPalette.red400).textSelection(.enabled)
            } else {
                board
            }
        case .done:
            board
        }
    }

    @ViewBuilder private var board: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let synthesis {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOMMENDATION").font(.system(size: 9, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(ALColor.accentText)
                    MarkdownText(markdown: synthesis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(ALColor.active, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            }
            ForEach(run?.workerAnswers ?? []) { answer in
                answerCard(answer)
            }
        }
    }

    private func answerCard(_ answer: WorkerAnswer) -> some View {
        let bench = appModel.composeBench.first { $0.id == answer.modelId }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let bench { DriverBrandGlyph(driverId: bench.driverId, boxSize: 18, iconSize: 9, cornerRadius: 5) }
                Text(bench?.name ?? answer.modelId)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(ALColor.textSecondary)
                Spacer(minLength: 0)
                StatusPill(kind: ThreadsPresenter.pillKind(for: workerTurnStatus(answer.status)))
            }
            switch answer.status {
            case .done:
                MarkdownText(markdown: answer.output ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed, .timedOut:
                Text(answer.errorReason ?? "No answer.")
                    .font(.system(size: 12.5)).foregroundStyle(ALPalette.red400).textSelection(.enabled)
            default:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("running…").font(.system(size: 12)).foregroundStyle(ALColor.textMuted)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }

    private func workerTurnStatus(_ status: WorkerAnswerStatus) -> ThreadTurnStatus {
        switch status {
        case .done: return .done
        case .failed: return .failed
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .running: return .running
        case .queued, .skipped: return .queued
        }
    }
}

// MARK: - Mutating run row

/// A mutating run in the repo. Renders from the durable `TeamRun` output.
private struct ThreadMutatingRunRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    let turn: ThreadTurn
    @State private var hovering = false

    private var run: TeamRun? {
        guard let runId = turn.runId else { return nil }
        return threads.teamRun(forRunId: runId)
    }
    private var runOutput: String? {
        if let markdown = run?.latestStage(.plan)?.payload?.markdown, !markdown.isEmpty { return markdown }
        return run?.workerAnswers.first { ($0.output ?? "").isEmpty == false }?.output
    }
    private var model: ComposeBenchModel? {
        guard let id = turn.workerId else { return nil }
        return appModel.composeBench.first { $0.id == id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            glyph
            VStack(alignment: .leading, spacing: 6) {
                header
                content
            }
            Spacer(minLength: 0)
        }
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var glyph: some View {
        if let model {
            DriverBrandGlyph(driverId: model.driverId, boxSize: 28, iconSize: 14, cornerRadius: 7)
        } else {
            Image(systemName: "terminal.fill").font(.system(size: 13)).foregroundStyle(ALColor.accent)
                .frame(width: 28, height: 28).background(ALColor.subtle, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(model?.name ?? turn.workerId ?? "Assistant")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(ALColor.textSecondary)
            Text(turn.createdAt, format: .dateTime.hour().minute())
                .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            Spacer(minLength: 8)
            if hovering, let out = runOutput, !out.isEmpty {
                IconButton(systemImage: "doc.on.doc", accessibilityLabel: "Copy", small: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(out, forType: .string)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch turn.status {
        case .running, .queued, .draft:
            VStack(alignment: .leading, spacing: 8) {
                ThreadThinkingBlock(text: turn.reasoningText)
                if let partial = turn.text, !partial.isEmpty {
                    // Live streamed text — plain while in flight so in-progress Markdown
                    // can't break layout; the settled state re-renders via Markdown.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(partial)
                            .font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(turn.partialOutputTruncated ? "streaming… (truncated)" : "streaming…")
                                .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(turn.reasoningText?.isEmpty == false ? "thinking…" : "Working…")
                            .font(.system(size: 12)).foregroundStyle(ALColor.textMuted)
                    }
                }
            }
        case .failed, .timedOut:
            // No durable run/return means a system note such as missing dir,
            // busy write lock, or no worker. Render it honestly.
            if runOutput == nil {
                Text(turn.text?.isEmpty == false ? (turn.text ?? "") : "The run failed.")
                    .font(.system(size: 13)).foregroundStyle(ALPalette.red400).textSelection(.enabled)
            } else {
                resultCard
            }
        case .done:
            resultCard
        case .cancelled:
            Text("Cancelled.").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
        }
    }

    // Clean assistant message in the flow — no status card, no "Ran" badge.
    @ViewBuilder private var resultCard: some View {
        if let runOutput {
            MarkdownText(markdown: runOutput)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(turn.text ?? "Done.").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
        }
    }

}
