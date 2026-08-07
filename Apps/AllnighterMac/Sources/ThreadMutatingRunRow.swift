import SwiftUI
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

// MARK: - Mutating run row

/// A mutating run in the repo. Renders from the durable `TeamRun` output.
struct ThreadMutatingRunRow: View {
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
                vendorDisplayName: vendor
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
