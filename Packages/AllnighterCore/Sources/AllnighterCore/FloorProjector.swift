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
        let stageArtifacts = stageRefs(for: run)
        let theReturn = floorReturn(for: run, leadWorkerId: lead?.id, stageArtifacts: stageArtifacts)
        let allArtifacts = lanes.flatMap { $0.artifactRefs + ($0.promptArtifactRef.map { [$0] } ?? []) }
            + stageArtifacts + [bundleRef(for: run)]

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
            floorReturn: theReturn,
            nextActions: baseNextActions(for: run),
            artifacts: allArtifacts,
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
            let createdAt = answer?.finishedAt ?? answer?.startedAt ?? run.createdAt
            let stem = RunArtifactRef.safeStem(worker.id)

            // Metadata exists for every worker — including failed/skipped/cancelled.
            var refs = [RunArtifactRef(
                id: "\(run.id)_\(stem)_meta", runId: run.id, kind: .workerMetadata,
                title: "\(worker.skillName ?? worker.id) metadata",
                relativePath: "workers/\(stem).metadata.json", mimeType: "application/json",
                workerId: worker.id, createdAt: createdAt)]
            // The durable answer markdown exists only when the worker produced output.
            if answer?.hasAnswer == true {
                refs.append(RunArtifactRef(
                    id: "\(run.id)_\(stem)_answer", runId: run.id, kind: .workerAnswer,
                    title: "\(worker.skillName ?? worker.id) answer",
                    relativePath: "workers/\(stem).answer.md", mimeType: "text/markdown",
                    workerId: worker.id, createdAt: createdAt))
            }
            let promptRef: RunArtifactRef? = worker.resolvedWorkerPromptSnapshot.map { _ in
                RunArtifactRef(
                    id: "\(run.id)_\(stem)_prompt", runId: run.id, kind: .workerPrompt,
                    title: "\(worker.skillName ?? worker.id) prompt",
                    relativePath: "workers/\(stem).prompt.md", mimeType: "text/markdown",
                    workerId: worker.id, createdAt: createdAt, localOnly: true)
            }

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
                artifactRefs: refs,
                promptArtifactRef: promptRef,
                error: answer?.errorReason
            )
        }
    }

    private static func bundleRef(for run: TeamRun) -> RunArtifactRef {
        RunArtifactRef(
            id: "\(run.id)_bundle", runId: run.id, kind: .bundle, title: "Run bundle",
            relativePath: "bundle.md", mimeType: "text/markdown", createdAt: run.createdAt)
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

    /// The stage that produced the user-facing return: final spec, else plan, else
    /// board (the synthesized output the Floor's right side shows).
    private static func returnStage(for run: TeamRun) -> StageOutput? {
        run.latestStage(.finalSpec) ?? run.latestStage(.plan) ?? run.latestStage(.board)
    }

    private static func stageMarkdown(_ stage: StageOutput?) -> String? {
        stage?.payload?.markdown   // board payloads are structured (options/chosen), not markdown
    }

    private static func floorReturn(for run: TeamRun, leadWorkerId: String?,
                                    stageArtifacts: [RunArtifactRef]) -> FloorReturn? {
        // The typed return, projected over the output stage (plan/board/final spec),
        // typed by output kind. F-S03 specializes Signal into a typed insight.
        guard let title = run.teamDisplayName ?? run.presetId else { return nil }
        let stage = returnStage(for: run)
        let markdown = stageMarkdown(stage)
        guard markdown != nil || run.status.isTerminal else { return nil }
        let refs = stage.map { s in stageArtifacts.filter { $0.stageId == s.id } } ?? []
        return FloorReturn(
            kind: returnKind(for: run.outputKind),
            status: status(for: run.status).rawValue,
            title: title,
            summaryMarkdown: markdown,
            producedByWorkerId: leadWorkerId,
            stageId: stage?.id,
            artifactRefs: refs
        )
    }

    /// Stage output artifact refs (F-S02): one per stage that produced markdown,
    /// matching the `stages/<id>.<purpose>.md` files RunStore writes.
    private static func stageRefs(for run: TeamRun) -> [RunArtifactRef] {
        run.stages.compactMap { stage in
            guard stageMarkdown(stage) != nil else { return nil }
            let stem = RunArtifactRef.safeStem(stage.id)
            return RunArtifactRef(
                id: "\(run.id)_stage_\(stem)", runId: run.id, kind: .stageOutput,
                title: "\(stage.purpose.rawValue) output",
                relativePath: "stages/\(stem).\(stage.purpose.rawValue).md", mimeType: "text/markdown",
                stageId: stage.id, createdAt: stage.finishedAt ?? run.createdAt)
        }
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
