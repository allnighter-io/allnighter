import SwiftUI
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

/// Driver glyph for an agent turn — brand when source is known, terminal fallback otherwise.
struct ThreadAgentGlyph: View {
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

/// Single row: `Agent · Opus 5 · 4:23 AM` or relay `Dev · Grok Build · 4:23 AM`.
struct ThreadAgentHeader: View {
    let label: ThreadAgentPresentation.Label
    let timestamp: Date

    var body: some View {
        HStack(spacing: 6) {
            Text(label.primary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ALColor.textSecondary)
            Text(timestamp, format: .dateTime.hour().minute())
                .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
        }
    }
}

struct ThreadTurnRow: View {
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
            // R-S08: the ONE open, actionable system event — a Loop round asked the
            // founder a real question and is waiting. ATL-S04: resume gating reads
            // `LoopState.isResumable` via `RelayResumeController` — never turn prose.
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
