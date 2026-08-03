import SwiftUI
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

// MARK: - CR4c team board

/// A team run result: the team's synthesis up top, then each model's answer as a
/// card. Renders from the durable TeamRun behind the turn's `runId` (turn → run →
/// answers + plan), so it always shows the real path — never a faked board.
struct ThreadBoardRow: View {
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
