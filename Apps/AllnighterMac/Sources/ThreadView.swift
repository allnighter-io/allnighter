import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

// Conversation thread pane (docs/phases/wiring/compose-routing, reference/app.jsx
// ThreadPane + NewPane). CR4a: userMessage turns + docked RoutingComposer; worker
// replies land in CR4b.

struct ThreadView: View {
    @Environment(ThreadsViewModel.self) private var threads

    var body: some View {
        if let thread = threads.selectedThread {
            ThreadPaneShell(thread: thread)
        }
    }
}

// MARK: - Thread shell (one composer — survives empty→conversation)

private struct ThreadPaneShell: View {
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread

    private var isEmpty: Bool { thread.turns.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if isEmpty {
                ThreadEmptyStateBody(thread: thread)
            } else {
                ThreadConversationBody(thread: thread)
            }
            if thread.isArchived {
                archivedComposerBar
            } else {
                ThreadDockedComposer(thread: thread, big: isEmpty)
                    .frame(maxWidth: isEmpty ? 640 : 680)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, isEmpty ? 28 : 20)
                    .padding(.vertical, isEmpty ? 28 : 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .overlay {
            if thread.isArchived && isEmpty {
                archivedComposerOverlay
            }
        }
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

// MARK: - Empty thread ("Start a run")

private struct ThreadEmptyStateBody: View {
    @Environment(AppModel.self) private var appModel
    let thread: WorkThread

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
        }
        .disabled(thread.isArchived)
    }
}

// MARK: - Thread with turns

private struct ThreadConversationBody: View {
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread

    var body: some View {
        VStack(spacing: 0) {
            ThreadPaneHeader(thread: thread)
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            ThreadTurnTimeline(thread: thread)
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
        }
        // ⌥⌘R toggles the whole conversation between rich markdown and raw selectable
        // source. A zero-size button just to own the keyboard shortcut.
        .background {
            Button("") { threads.showRawAnswers.toggle() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Docked composer (thread-scoped continuation)

/// One composer per thread — pins the last model used so session continuation survives
/// turn settlement, empty→conversation transitions, and rail switches.
private struct ThreadDockedComposer: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread
    var big: Bool = false

    private var continuationModelId: String? {
        ThreadsPresenter.continuationModelId(
            for: thread,
            benchModelIds: Set(appModel.composeBench.map(\.id))
        )
    }

    var body: some View {
        RoutingComposer(
            big: big,
            continuationModelId: continuationModelId,
            onSend: { threads.sendRouting($0) }
        )
        .id(thread.id)
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
        return thread.turns.compactMap(\.modelId).filter { seen.insert($0).inserted }
    }

    /// Distinct model display names that have answered in this thread. A worker id is
    /// `modelId#instanceIndex` (Agent.makeID), so strip the suffix before resolving.
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
    /// RLS-S04: true while the user is parked at the bottom — gates live follow-scroll so a
    /// streaming answer keeps itself in view, but a manual scroll-up is never fought.
    @State private var atBottom = true
    private static let bottomAnchorId = "__timeline_bottom__"

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { outer in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(thread.turns) { turn in
                            ThreadTurnRow(turn: turn, isLastTurn: turn.id == thread.turns.last?.id)
                                .id(turn.id)
                                .timelineTurnFrame(turnId: turn.id)
                        }
                        // Bottom sentinel — reports the content's bottom edge so live
                        // follow-scroll only fires when the user is already at the bottom.
                        Color.clear.frame(height: 1)
                            .id(Self.bottomAnchorId)
                            .background(GeometryReader { g in
                                Color.clear.preference(
                                    key: TimelineBottomSentinelKey.self,
                                    value: g.frame(in: .global).maxY)
                            })
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .timelineVisibilityTracking(thread: thread)
                .onPreferenceChange(TimelineBottomSentinelKey.self) { sentinelMaxY in
                    atBottom = TimelineScrollPolicy.isAtBottom(
                        contentBottomY: sentinelMaxY, viewportBottomY: outer.frame(in: .global).maxY)
                }
                .onAppear { scrollTimelineToOpenPosition(proxy: proxy) }
                .onChange(of: thread.id) { _, _ in scrollTimelineToOpenPosition(proxy: proxy) }
                .onChange(of: thread.turns.count) { _, _ in
                    TimelineScrollPolicy.scrollOnTurnCountChange(
                        proxy: proxy,
                        thread: thread,
                        suppressAutoScroll: GUIFixture.suppressUnreadAutoScroll,
                        forceScrollToBottomAfterSend: threads.forceScrollToBottomAfterSendActive(),
                        bottomAnchorId: Self.bottomAnchorId
                    )
                }
                .onChange(of: TimelineScrollPolicy.liveContentSignal(for: thread)) { _, _ in
                    // RLS-S04: follow the streaming answer as it grows — but only when the
                    // user is at the bottom, and without animation so the follow stays tight.
                    guard !GUIFixture.suppressUnreadAutoScroll else { return }
                    if threads.forceScrollToBottomAfterSendActive() || atBottom {
                        TimelineScrollPolicy.scrollToBottom(
                            proxy: proxy,
                            bottomAnchorId: Self.bottomAnchorId,
                            animated: false
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollTimelineToOpenPosition(proxy: ScrollViewProxy) {
        TimelineScrollPolicy.scrollOnThreadOpen(
            proxy: proxy,
            pendingTarget: threads.consumePendingScrollTarget(),
            suppressAutoScroll: GUIFixture.suppressUnreadAutoScroll,
            bottomAnchorId: Self.bottomAnchorId
        )
    }
}

/// Reasoning render policy. The latest, still-running turn auto-expands so live thinking
/// is visible — a collapsed "Thinking" header alone reads as a frozen screen. A settled
/// turn collapses back to the compact "Thought for Ns" summary (reasoning is audit/debug
/// once the answer exists). An explicit user toggle always wins. RLS-P0: the auto-expanded
/// running view is height-bounded and tail-scrolled (see `ThreadThinkingBlock`) so streaming
/// reasoning can't lay out an ever-taller `Text` on every delta.
enum ReasoningRenderPolicy {
    static func expanded(userToggle: Bool?, isLatestTurn: Bool, isRunning: Bool) -> Bool {
        if let userToggle { return userToggle }
        return isLatestTurn && isRunning
    }
}

/// Compact wall-clock duration: "8s", "1m 20s", "1h 3m". No leading zero units.
enum DurationFormat {
    static func compact(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

/// A running-state label that ticks the elapsed wall time each second — "Working 8s",
/// "Thinking 1m 20s" — so a spinner reads as live progress, not a hang (some workers, e.g.
/// AGY/Gemini, never stream thoughts, so the clock is the only sign of life). `TimelineView`
/// pauses when offscreen, and the caller renders this only while the turn runs, so it stops
/// at settlement. The clock is wall time on our side (includes queue/spawn) — what the user
/// actually waits.
private struct RunningStatusLabel: View {
    let verb: String
    let start: Date
    var suffix: String = ""
    var font: Font = .system(size: 12)
    var color: Color = ALColor.textMuted

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            Text("\(verb) \(DurationFormat.compact(context.date.timeIntervalSince(start)))\(suffix)")
                .font(font).foregroundStyle(color).monospacedDigit()
        }
    }
}

/// Spinner + the live "Streaming Ns" clock for a turn whose answer text is mid-stream.
/// Shared by the worker-chat and mutating-run rows (one place to evolve the affordance).
private struct StreamingIndicator: View {
    let start: Date
    let truncated: Bool
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            RunningStatusLabel(
                verb: "Streaming", start: start,
                suffix: truncated ? " (truncated)" : "",
                font: .system(size: 11), color: ALColor.textFaint)
        }
    }
}

/// Spinner + the pre-answer activity label, shared by the worker-chat and mutating-run rows.
/// While actually running it ticks ("Thinking Ns" when reasoning streams into the bar above,
/// else "Working Ns"); a not-yet-started turn (queued/draft) shows a static "Queued…" rather
/// than a clock counting from creation.
private struct WorkingIndicator: View {
    let turn: ThreadTurn
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            if turn.status == .running {
                if turn.reasoningText?.isEmpty == false {
                    Text("Thinking…").font(.system(size: 12)).foregroundStyle(ALColor.textMuted)
                } else {
                    RunningStatusLabel(verb: "Working", start: turn.createdAt)
                }
            } else {
                Text("Queued…").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
            }
        }
    }
}

/// CR4a user messages + CR4b worker chat replies; team/mutating run turns render
/// from durable run truth.
/// The model's reasoning, kept above (and visually under) the answer. Collapsed by
/// default (a compact "Thinking…/Thought for Ns" header); a click reveals the full text.
private struct ThreadThinkingBlock: View {
    let text: String?
    var isLatestTurn: Bool = false
    var isRunning: Bool = false
    var duration: TimeInterval? = nil
    /// When running, the turn's start — drives the live "Thinking Ns" clock in the bar.
    var startedAt: Date? = nil
    /// nil = use the default policy (collapsed); set by a manual toggle.
    @State private var userExpanded: Bool? = nil

    private let tailAnchorID = "reasoning-tail"

    private var expanded: Bool {
        ReasoningRenderPolicy.expanded(userToggle: userExpanded, isLatestTurn: isLatestTurn, isRunning: isRunning)
    }

    /// The reasoning prose itself — selectable, wraps, grows down.
    private func reasoningText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12)).foregroundStyle(ALColor.textMuted)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerLabel: String {
        if isRunning { return "Thinking" }
        if let duration, duration >= 1 { return "Thought for \(DurationFormat.compact(duration))" }
        return "Thought process"
    }

    var body: some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: expanded ? 4 : 0) {
                Button { userExpanded = !expanded } label: {
                    HStack(spacing: 5) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold)).foregroundStyle(ALColor.textFaint)
                        Image(systemName: "brain").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
                        if isRunning, let startedAt {
                            RunningStatusLabel(
                                verb: "Thinking", start: startedAt,
                                font: .system(size: 10, weight: .semibold), color: ALColor.textFaint)
                                .tracking(0.4)
                        } else {
                            Text(headerLabel).font(.system(size: 10, weight: .semibold)).tracking(0.4)
                                .foregroundStyle(ALColor.textFaint)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    if isRunning {
                        // RLS-P0: while streaming, cap the height and pin to the tail so live
                        // reasoning shows the newest text without laying out an ever-taller
                        // view on every delta. Settled turns render full (no cap).
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                reasoningText(text)
                                Color.clear.frame(height: 1).id(tailAnchorID)
                            }
                            .frame(maxHeight: 180)
                            .onChange(of: text) { _, _ in
                                proxy.scrollTo(tailAnchorID, anchor: .bottom)
                            }
                            // Pin to the newest text on first paint too — an already-long
                            // reasoning (resumed / late-rendered) must not open scrolled to the top.
                            .onAppear { proxy.scrollTo(tailAnchorID, anchor: .bottom) }
                        }
                    } else {
                        reasoningText(text)
                    }
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
    }
}

/// Always-visible "Copy" button at the foot of every agent answer. The markdown
/// renderer doesn't reliably support text selection, so this is the dependable way to
/// get an answer onto the clipboard. Shows a "Copied" confirmation.
/// A settled agent answer: rich markdown OR raw selectable source (conversation-wide,
/// toggled by ⌥⌘R / the footer), with a footer carrying the Raw⇄Rendered toggle, an
/// auto-copy "Copied" flash (raw drag-select), and the explicit Copy button.
private struct AnswerBody: View {
    @Environment(ThreadsViewModel.self) private var threads
    let markdown: String
    @State private var copiedFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if threads.showRawAnswers {
                    SelectableText(text: markdown, onCopied: { _ in flashCopied() })
                } else {
                    MarkdownText(markdown: markdown)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if !markdown.isEmpty {
            HStack(spacing: 8) {
                Button { threads.showRawAnswers.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 10, weight: .medium))
                        Text(threads.showRawAnswers ? "Rendered" : "Raw").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(ALColor.textMuted)
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(ALColor.subtle, in: Capsule())
                    .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .help(threads.showRawAnswers
                      ? "Show rendered markdown (⌥⌘R)"
                      : "Show raw text — drag to select, auto-copies (⌥⌘R)")

                if copiedFlash {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        Text("Copied").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(ALPalette.green500)
                    .transition(.opacity)
                }
                Spacer(minLength: 0)
                CopyButton(text: markdown)
            }
            .padding(.top, 3)
            .animation(.easeInOut(duration: 0.15), value: copiedFlash)
        }
    }

    private func flashCopied() {
        copiedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedFlash = false }
    }
}

/// The explicit one-click "Copy this answer" button (shared chrome).
private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
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
        .help("Copy this answer")
    }
}

/// Driver glyph for an agent turn — brand when source is known, terminal fallback otherwise.
private struct ThreadAgentGlyph: View {
    let driverId: String?

    var body: some View {
        Group {
            if let driverId {
                DriverBrandGlyph(driverId: driverId, boxSize: 28, iconSize: 14, cornerRadius: 7)
            } else {
                Image(systemName: "terminal.fill").font(.system(size: 13)).foregroundStyle(ALColor.accent)
                    .frame(width: 28, height: 28).background(ALColor.subtle, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

/// Plain chat: `Agent · Opus 5`. Relay: bold `Agent` + faint `Opus 5 · Claude · PM`.
private struct ThreadAgentHeader: View {
    let label: ThreadAgentPresentation.Label
    let timestamp: Date

    var body: some View {
        HStack(spacing: 6) {
            switch label.layout {
            case .plain:
                Text(label.primary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ALColor.textSecondary)
            case .relay:
                VStack(alignment: .leading, spacing: 1) {
                    Text(label.primary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ALColor.textSecondary)
                    if let secondary = label.secondary {
                        Text(secondary)
                            .font(ALFont.monoSm)
                            .foregroundStyle(ALColor.textFaint)
                            .lineLimit(1)
                    }
                }
            }
            Text(timestamp, format: .dateTime.hour().minute())
                .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
        }
    }
}

private struct ThreadTurnRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    let turn: ThreadTurn
    var isLastTurn: Bool = false
    @State private var hovering = false

    /// How long the model spent before settling (for the collapsed "Thought for Ns").
    private var thinkingDuration: TimeInterval? {
        turn.completedAt.map { $0.timeIntervalSince(turn.createdAt) }
    }

    var body: some View {
        switch turn.kind {
        case .userMessage, .userDecision:
            userBubble
        case .workerChat:
            workerBubble
        case .teamRun, .designBoard, .reviewBoard:
            ThreadBoardRow(turn: turn)
        case .mutatingRun:
            ThreadMutatingRunRow(turn: turn, isLastTurn: isLastTurn)
        case .systemEvent where turn.systemEvent == .relayEscalated && turn.status == .running:
            // R-S08: the ONE open, actionable system event — a PM Relay round asked the
            // founder a real question and is waiting. Every other system event (including
            // an already-resumed/settled relayEscalated turn) stays the plain stub below.
            RelayEscalationRow(turn: turn)
        default:
            stubTurn
        }
    }

    // CR4b — one model's reply.
    private var agentLabel: ThreadAgentPresentation.Label {
        appModel.threadAgentLabel(for: turn)
    }

    private var resolvedAttachments: [ResolvedThreadAttachment] {
        threads.resolvedAttachments(threadId: turn.threadId, turn: turn)
    }

    private var attachmentRow: some View {
        TimelineAttachmentRow(
            attachments: resolvedAttachments,
            thumb: { threads.attachmentThumb(for: $0) },
            onOpen: { threads.openAttachmentPath($0.canonicalPath) },
            onReveal: { threads.revealAttachmentInFinder($0.canonicalPath) },
            onCopy: { threads.copyAttachmentImage($0) }
        )
    }

    private var workerBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            ThreadAgentGlyph(driverId: agentLabel.driverId)
            VStack(alignment: .leading, spacing: 6) {
                ThreadAgentHeader(label: agentLabel, timestamp: turn.createdAt)
                // Thinking persists across running → done (never removed → no jump);
                // expanded on the latest turn, collapsed to one line on prior turns.
                ThreadThinkingBlock(
                    text: turn.reasoningText, isLatestTurn: isLastTurn,
                    isRunning: !turn.status.isTerminal, duration: thinkingDuration,
                    startedAt: turn.createdAt)
                switch turn.status {
                case .running, .queued, .draft:
                    if let partial = turn.text, !partial.isEmpty {
                        // Live streaming text — PLAIN while running so malformed
                        // in-progress Markdown can't break layout; the settled .done
                        // state re-renders through the Markdown engine.
                        VStack(alignment: .leading, spacing: 4) {
                            Text(partial)
                                .font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                                // RLS-S04: selection on actively-streaming text recomputes
                                // selectable ranges on every delta (and the workspace root
                                // enables selection by inheritance). Disable it while in
                                // flight; selection returns at settlement via the answer's
                                // markdown/raw toggle.
                                .textSelection(.disabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            StreamingIndicator(start: turn.createdAt, truncated: turn.partialOutputTruncated)
                        }
                    } else {
                        WorkingIndicator(turn: turn)
                    }
                case .failed, .timedOut:
                    Text(turn.text?.isEmpty == false ? (turn.text ?? "") : "The worker failed.")
                        .font(.system(size: 13))
                        .foregroundStyle(ALPalette.red400)
                        .textSelection(.enabled)
                case .cancelled:
                    Text("Cancelled.").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
                case .done:
                    if !resolvedAttachments.isEmpty {
                        attachmentRow
                    }
                    if let text = turn.text, !text.isEmpty {
                        AnswerBody(markdown: text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .onHover { hovering = $0 }
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
                if !resolvedAttachments.isEmpty {
                    attachmentRow
                }
                if let text = turn.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 13.5))
                        .foregroundStyle(ALColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
                        .textSelection(.enabled)
                }
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

// MARK: - R-S08 relay escalation (resume-from-GUI)

/// The one place a PM Relay round asks the founder a real question
/// (`docs/phases/PM_Relay.md` §4.1) and stops. `turn.threadId` IS the relay id
/// (`RelayThreadProjector`'s identity rule — no separate lookup). No existing composer
/// seam answers an open system event inline (`ThreadTurnRow` had no case for
/// `.systemEvent` at all before this), so this ships as its own affordance rather than
/// routing through `RoutingComposer`/`sendRouting` — see `RelayResumeController`'s doc
/// comment for why that would be invasive surgery instead of seam reuse.
private struct RelayEscalationRow: View {
    @Environment(RelayResumeController.self) private var relayResume
    @Environment(ThreadsViewModel.self) private var threads
    let turn: ThreadTurn
    @State private var answer = ""
    @FocusState private var answerFocused: Bool

    private var relayId: String { turn.threadId }
    private var isResuming: Bool { relayResume.isResuming(relayId) }
    private var canSubmit: Bool { !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResuming }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 13)).foregroundStyle(ALPalette.amber400)
                Text("PM Relay needs an answer").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
            }
            if let note = turn.text, !note.isEmpty {
                Text(note).font(.system(size: 13)).foregroundStyle(ALColor.textSecondary).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                TextField("Your answer…", text: $answer, onCommit: submit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($answerFocused)
                    .padding(.horizontal, 10).frame(height: ALControl.height)
                    .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                    .overlay { RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                    .disabled(isResuming)
                Button(isResuming ? "Resuming…" : "Answer & resume", action: submit)
                    .buttonStyle(.alPrimary)
                    .disabled(!canSubmit)
            }
            if let error = relayResume.lastError[relayId] {
                Text(error).font(.system(size: 11)).foregroundStyle(ALPalette.red400)
            }
        }
        .padding(12)
        .background(ALColor.warningSurface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.accentBorder, lineWidth: 1) }
    }

    private func submit() {
        guard canSubmit else { return }
        let text = answer
        // `RelayCoordinator.resume` — same construction path as launch
        // (`RelayGUIRuntime.makeCoordinator`), never a normal chat turn.
        guard relayResume.resume(relayId: relayId, answer: text, onEvent: { _ in
            Task { @MainActor in threads.requestReload() }
        }) else { return }
        answer = ""
        answerFocused = false
    }
}

// MARK: - CR4c team board

/// A team run result: the team's synthesis up top, then each model's answer as a
/// card. Renders from the durable TeamRun behind the turn's `runId` (turn → run →
/// answers + plan), so it always shows the real path — never a faked board.
private struct ThreadBoardRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(\.openFloor) private var openFloor
    let turn: ThreadTurn
    /// Agent answers render lazily — only an expanded card parses/lays out its full
    /// markdown, so first paint of a big terminal team run stays fast (perf doc).
    @State private var expanded: Set<String> = []

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
            if let n = run?.answers.count, n > 0 {
                Text("· \(n) models").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            Text(turn.createdAt, format: .dateTime.hour().minute())
                .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
        }
    }

    @ViewBuilder private var content: some View {
        switch turn.status {
        case .running, .queued, .draft:
            if turn.kind == .teamRun, let runId = turn.runId,
               let live = threads.liveArtifact(forRunId: runId), !live.seatList.isEmpty {
                LiveArtifactPreviewView(state: live, isLive: true)
            } else if turn.kind == .teamRun, let runId = turn.runId,
                      let run = threads.teamRun(forRunId: runId) {
                LiveArtifactPreviewView(
                    state: LiveArtifactProjector.seed(
                        run: run, context: .init(models: appModel.models)),
                    isLive: true)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    RunningStatusLabel(verb: "Fanning out", start: turn.createdAt)
                }
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

    /// Images the team's worker(s) produced, captured into thread attachments at settlement
    /// (non-design boards — design uses the tile strip). Click opens the canonical file.
    @ViewBuilder private var attachmentRow: some View {
        let resolved = threads.resolvedAttachments(threadId: turn.threadId, turn: turn)
        if turn.kind != .designBoard, !resolved.isEmpty {
            TimelineAttachmentRow(
                attachments: resolved,
                thumb: { threads.attachmentThumb(for: $0) },
                onOpen: { threads.openAttachmentPath($0.canonicalPath) },
                onReveal: { threads.revealAttachmentInFinder($0.canonicalPath) },
                onCopy: { threads.copyAttachmentImage($0) }
            )
        }
    }

    @ViewBuilder private var board: some View {
        VStack(alignment: .leading, spacing: 10) {
            attachmentRow
            if turn.kind == .designBoard, let run, let board = run.latestStage(.board)?.payload?.board {
                DesignBoardTileStrip(
                    board: board,
                    runDirectory: threads.runDirectory(forRunId: run.id),
                    onOpenBoard: { openFloor(run) }
                )
            } else if turn.kind == .designBoard, run != nil {
                Text("Design board payload is not available yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(ALColor.textMuted)
            }
            if let run, run.status.isTerminal, turn.kind != .designBoard {
                HStack(spacing: 8) {
                    Button { openFloor(run) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.split.3x1.fill").font(.system(size: 10))
                            Text("Open Factory Floor").font(.system(size: 12, weight: .medium))
                            Image(systemName: "arrow.up.right").font(.system(size: 9))
                        }
                        .foregroundStyle(ALColor.accentText)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(ALColor.active, in: Capsule())
                        .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .help("Open the full reader: every worker answer, synthesis, and receipts")
                    if turn.kind == .teamRun {
                        Button {
                            ArtifactFloorOpener.openArtifact(for: run, models: appModel.models)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.richtext").font(.system(size: 10))
                                Text("Open artifact").font(.system(size: 12, weight: .medium))
                                Image(systemName: "arrow.up.right").font(.system(size: 9))
                            }
                            .foregroundStyle(ALColor.textSecondary)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(ALColor.raised, in: Capsule())
                            .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate and open the polished HTML team artifact in your browser")
                    }
                }
            }
            if let synthesis, turn.kind != .designBoard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOMMENDATION").font(.system(size: 9, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(ALColor.accentText)
                    AnswerBody(markdown: synthesis)
                }
                .padding(12)
                .background(ALColor.active, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            }
            if turn.kind != .designBoard {
                ForEach(run?.answers ?? []) { answer in
                    answerCard(answer)
                }
            }
        }
    }

    /// The worker's job title for this answer — the skill name, else a humanized skill id,
    /// else a generic fallback (never the raw `model_x#0` worker id).
    private func workerTitle(_ answer: TeamAnswer) -> String {
        let worker = run?.workers.first { $0.id == answer.memberId }
        if let name = worker?.skillName, !name.isEmpty { return name }
        if let id = worker?.skillId, !id.isEmpty {
            return id.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        return "Agent"
    }

    /// One-glance plain-text preview for a collapsed answer (no markdown layout cost).
    private func answerPreview(_ output: String?) -> String {
        let flat = (output ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.isEmpty ? "Show answer" : String(flat.prefix(220))
    }

    private func answerCard(_ answer: TeamAnswer) -> some View {
        let bench = appModel.composeBench.first { $0.id == answer.modelId }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let bench { DriverBrandGlyph(driverId: bench.driverId, boxSize: 18, iconSize: 9, cornerRadius: 5) }
                // Agent JOB/TITLE first, then the model (bug #1) — so you can tell who did
                // what, not just which model ran.
                VStack(alignment: .leading, spacing: 1) {
                    Text(workerTitle(answer))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ALColor.textSecondary).lineLimit(1)
                    Text(bench?.name ?? answer.modelId)
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint).lineLimit(1)
                }
                Spacer(minLength: 0)
                StatusPill(kind: ThreadsPresenter.pillKind(for: workerTurnStatus(answer.result.status)))
            }
            switch answer.result.status {
            case .done:
                if expanded.contains(answer.id) {
                    AnswerBody(markdown: answer.output ?? "")
                } else {
                    // Lazy preview — tap to render the full markdown (keeps first paint cheap).
                    Button { expanded.insert(answer.id) } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Text(answerPreview(answer.output))
                                .font(.system(size: 12.5)).foregroundStyle(ALColor.textMuted)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            case .failed, .timedOut:
                // Honest, distinct cause (#8) — auth / rate limit / wrong CLI / timeout /
                // no-output — not a single collapsed "timed out". Partial output preserved below.
                VStack(alignment: .leading, spacing: 5) {
                    Text(WorkerFailurePresenter.cause(
                        status: answer.result.status, errorKind: answer.result.errorKind,
                        errorReason: answer.result.errorReason, capacity: answer.result.capacityObservation) ?? "No answer.")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(ALPalette.red400).textSelection(.enabled)
                    if WorkerFailurePresenter.hasPartialOutput(answer.output) {
                        Text(answer.output ?? "")
                            .font(.system(size: 12.5)).foregroundStyle(ALColor.textMuted).textSelection(.enabled)
                    }
                }
            case .cancelled:
                Text("Cancelled.").font(.system(size: 12.5)).foregroundStyle(ALColor.textMuted)
            case .skipped:
                Text("Skipped.").font(.system(size: 12.5)).foregroundStyle(ALColor.textFaint)
            case .running:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    // Anchor to THIS worker's own start, not the whole board's, and only while
                    // actually running — a cancelled/skipped worker must not tick forever.
                    RunningStatusLabel(verb: "Working", start: answer.result.timing.startedAt ?? turn.createdAt)
                }
            case .queued:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Queued…").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
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
    var isLastTurn: Bool = false
    @State private var hovering = false

    private var thinkingDuration: TimeInterval? {
        turn.completedAt.map { $0.timeIntervalSince(turn.createdAt) }
    }

    private var run: TeamRun? {
        guard let runId = turn.runId else { return nil }
        return threads.teamRun(forRunId: runId)
    }
    private var runOutput: String? {
        if let markdown = run?.latestStage(.plan)?.payload?.markdown, !markdown.isEmpty { return markdown }
        return run?.answers.first { ($0.output ?? "").isEmpty == false }?.output
    }

    private var agentLabel: ThreadAgentPresentation.Label {
        appModel.threadAgentLabel(for: turn)
    }

    private var resolvedAttachments: [ResolvedThreadAttachment] {
        threads.resolvedAttachments(threadId: turn.threadId, turn: turn)
    }

    /// Images the worker produced, captured into thread attachments at settlement. Click
    /// opens the canonical file full size (Preview); right-click reveals/copies.
    @ViewBuilder private var attachmentRow: some View {
        let resolved = resolvedAttachments
        if !resolved.isEmpty {
            TimelineAttachmentRow(
                attachments: resolved,
                thumb: { threads.attachmentThumb(for: $0) },
                onOpen: { threads.openAttachmentPath($0.canonicalPath) },
                onReveal: { threads.revealAttachmentInFinder($0.canonicalPath) },
                onCopy: { threads.copyAttachmentImage($0) }
            )
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThreadAgentGlyph(driverId: agentLabel.driverId)
            VStack(alignment: .leading, spacing: 6) {
                ThreadAgentHeader(label: agentLabel, timestamp: turn.createdAt)
                // Persistent thinking surface — expanded on the latest turn, collapsed
                // to one line on prior turns. Never removed (no jump at settlement).
                ThreadThinkingBlock(
                    text: turn.reasoningText, isLatestTurn: isLastTurn,
                    isRunning: !turn.status.isTerminal, duration: thinkingDuration,
                    startedAt: turn.createdAt)
                parkBanner
                attachmentRow
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .onHover { hovering = $0 }
    }

    /// The caption to render. When the turn carries captured worker images, the settled
    /// `turn.text` is the cleaned caption (paths stripped), so prefer it over the raw run
    /// output that still holds the path; otherwise show the run's plan/answer.
    private var displayText: String? {
        if !resolvedAttachments.isEmpty, let t = turn.text, !t.isEmpty { return t }
        if let out = runOutput, !out.isEmpty { return out }
        if let t = turn.text, !t.isEmpty { return t }
        return nil
    }

    @ViewBuilder private var parkBanner: some View {
        if let run,
           run.status == .queued,
           run.phase == .waitingForVendor,
           let blocker = run.blocker,
           blocker.resource == .vendorBackoff {
            let source = blocker.capacityObservation?.source ?? blocker.quotaScope ?? "vendor"
            let vendor = VendorContinuityPresentation.vendorDisplayName(sourceId: source)
            let status = VendorContinuityPresentation.waitStatus(
                vendorDisplayName: vendor,
                wakeAfter: blocker.wakeAfter
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(status)
                    .font(.system(size: 13))
                    .foregroundStyle(ALColor.accent)
                HStack(spacing: 8) {
                    Button("Resume now") {
                        Task { await threads.resumeParkedVendorRun(runId: run.id) }
                    }
                    .buttonStyle(.bordered)
                    Button("Cancel") {
                        Task { await threads.cancelParkedVendorRun(runId: run.id) }
                    }
                    .buttonStyle(.borderless)
                    let substitutes = threads.vendorSubstitutionCandidates(for: run)
                    if substitutes.isEmpty {
                        Text("Use another model")
                            .font(.system(size: 12))
                            .foregroundStyle(ALColor.textFaint)
                    } else if substitutes.count == 1, let only = substitutes.first {
                        Button("Use another model") {
                            Task {
                                await threads.substituteParkedVendorRun(
                                    runId: run.id,
                                    modelId: only.id
                                )
                            }
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Menu("Use another model") {
                            ForEach(substitutes, id: \.id) { candidate in
                                Button(candidate.displayName) {
                                    Task {
                                        await threads.substituteParkedVendorRun(
                                            runId: run.id,
                                            modelId: candidate.id
                                        )
                                    }
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }
            .padding(10)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder private var content: some View {
        switch turn.status {
        case .running, .queued, .draft:
            if let partial = turn.text, !partial.isEmpty {
                // Live streamed text — plain while in flight so in-progress Markdown
                // can't break layout; the settled state re-renders via Markdown.
                VStack(alignment: .leading, spacing: 4) {
                    Text(partial)
                        .font(.system(size: 13)).foregroundStyle(ALColor.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    StreamingIndicator(start: turn.createdAt, truncated: turn.partialOutputTruncated)
                }
            } else {
                WorkingIndicator(turn: turn)
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
    // AnswerBody carries the conversation-wide Raw⇄Rendered toggle + Copy footer.
    @ViewBuilder private var resultCard: some View {
        if let displayText {
            AnswerBody(markdown: displayText)
        } else {
            Text("Done.").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
        }
    }

}
