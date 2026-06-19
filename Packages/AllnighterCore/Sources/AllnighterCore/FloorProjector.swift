import Foundation

/// Projects a persisted `TeamRun` into the public `FloorRun` (F-S00). Pure and
/// deterministic — no filesystem, no run store. Later slices enrich the result
/// (artifacts F-S01, typed return F-S02/S03, timeline F-S04, rich next actions +
/// Execute requirements F-S05) without changing this contract's shape.
public enum FloorProjector {
    public static func project(
        _ run: TeamRun,
        reproduceCommand: String? = nil,
        runJournalPath: String? = nil,
        traceId: String? = nil
    ) -> FloorRun {
        let lanes = workerLanes(for: run)
        let lead = run.workers.first { $0.purpose == .plan }

        let runInfo = FloorRun.Run(
            id: run.id,
            threadId: run.threadId,
            status: status(for: run.status),
            family: run.lane?.rawValue,
            posture: run.posture?.rawValue,
            mutating: run.mutating,
            origin: run.origin.rawValue,
            originAgent: run.originAgent,
            createdAt: run.createdAt,
            reproduceCommand: reproduceCommand
        )

        let team = FloorRun.Team(
            teamId: run.presetId,
            displayName: run.teamDisplayName,
            family: run.lane?.rawValue,
            outputKind: run.outputKind?.rawValue,
            workerCount: run.workers.count,
            modelCount: Set(run.workers.map(\.modelId)).count,
            leadWorkerId: lead?.id
        )

        return FloorRun(
            run: runInfo,
            intent: FloorRun.Intent(prompt: run.prompt, threadId: run.threadId),
            team: team,
            workerLanes: lanes,
            floorReturn: floorReturn(for: run, leadWorkerId: lead?.id),
            nextActions: baseNextActions(for: run),
            warnings: run.warnings,
            errors: workerErrors(for: run),
            audit: FloorRun.Audit(runJournalPath: runJournalPath, traceId: traceId)
        )
    }

    // MARK: - Mapping

    static func status(for s: RunStatus) -> FloorRun.Status {
        switch s {
        case .draft: return .queued
        case .fanningOut, .answersIn, .planning, .reviewing, .finalizing: return .running
        case .complete, .partial: return .done
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .interrupted: return .interrupted
        }
    }

    private static func lanePurpose(_ stage: WorkerStage?) -> FloorWorkerLane.Purpose {
        switch stage {
        case .answer: return .answer
        case .review: return .review
        case .plan: return .lead
        case .none: return .answer
        }
    }

    private static func workerLanes(for run: TeamRun) -> [FloorWorkerLane] {
        run.workers.map { worker in
            let answer = run.workerAnswer(workerId: worker.id)
            return FloorWorkerLane(
                workerId: worker.id,
                skillId: worker.skillId,
                skillName: worker.skillName,
                modelId: worker.modelId,
                purpose: lanePurpose(worker.purpose),
                status: (answer?.status ?? .queued).rawValue,
                startedAt: answer?.startedAt,
                finishedAt: answer?.finishedAt,
                durationMs: answer?.durationMs,
                exitCode: answer?.exitCode,
                summary: excerpt(answer?.output),
                error: answer?.errorReason
            )
        }
    }

    private static func workerErrors(for run: TeamRun) -> [ErrorEnvelope] {
        // A failed worker is always visible, even when synthesis succeeded.
        run.failedWorkerAnswers.map { a in
            ErrorEnvelope(
                code: "WORKER_FAILED",
                ruleId: "worker.failed",
                message: a.errorReason ?? "worker \(a.workerId) failed",
                requiresManual: false,
                retryable: true,
                workerId: a.workerId
            )
        }
    }

    private static func floorReturn(for run: TeamRun, leadWorkerId: String?) -> FloorReturn? {
        // F-S00 basic return: the synthesized plan markdown when present, typed by
        // output kind. F-S02/S03 enrich (board payloads, Signal insight).
        guard let title = run.teamDisplayName ?? run.presetId else { return nil }
        let markdown = run.plan
        guard markdown != nil || run.status.isTerminal else { return nil }
        return FloorReturn(
            kind: returnKind(for: run.outputKind),
            status: status(for: run.status).rawValue,
            title: title,
            summaryMarkdown: markdown,
            producedByWorkerId: leadWorkerId
        )
    }

    static func returnKind(for outputKind: TeamOutputKind?) -> FloorReturn.Kind {
        switch outputKind {
        case .insight: return .insight
        case .plan: return .plan
        case .proofPacket: return .proofPacket
        case .bugPacket, .securityRegister, .architectureVerdict: return .audit
        case .designBoard, .polishBoard, .copyBoard: return .board
        case .none: return .plan
        }
    }

    private static func baseNextActions(for run: TeamRun) -> [FloorNextAction] {
        // F-S00 emits only the safe, non-mutating actions. F-S05 adds Send-team,
        // Copy/Code/Design routing, Pending, and Execute (with Execute requirements).
        var actions: [FloorNextAction] = [
            FloorNextAction(id: "show_run", kind: .showRun, label: "Open run",
                            command: "alln show \(run.id) --json"),
            FloorNextAction(id: "show_history", kind: .showHistory, label: "Search history",
                            command: "alln history --json")
        ]
        if run.plan != nil {
            actions.insert(FloorNextAction(id: "copy_return", kind: .copyReturn, label: "Copy return"), at: 0)
        }
        return actions
    }

    private static func excerpt(_ text: String?, max: Int = 280) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.count <= max { return text }
        return String(text.prefix(max)) + "…"
    }
}
