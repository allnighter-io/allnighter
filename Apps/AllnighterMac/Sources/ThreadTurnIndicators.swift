import SwiftUI
import AllnighterCore

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
struct RunningStatusLabel: View {
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
struct StreamingIndicator: View {
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
struct WorkingIndicator: View {
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
struct ThreadThinkingBlock: View {
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
