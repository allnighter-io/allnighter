import Foundation

/// Projects a persisted `TeamRun` into the public `FloorRun` (F-S00). Pure and
/// deterministic — no filesystem, no run store. Later slices enrich the result
/// (artifacts F-S01, typed return F-S02/S03, timeline F-S04, rich next actions)
/// without changing this contract's shape.
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
            timeline: timeline(for: run),
            warnings: run.warnings,
            errors: workerErrors(for: run),
            audit: FloorRun.Audit(runJournalPath: runJournalPath, traceId: traceId)
        )
    }

    // MARK: - Mapping

    static func status(for s: RunStatus) -> FloorRun.Status {
        switch s {
        case .draft, .queued: return .queued
        case .running, .fanningOut, .answersIn, .planning, .reviewing, .finalizing: return .running
        case .complete, .partial, .done: return .done
        case .timedOut: return .timedOut
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .interrupted: return .interrupted
        }
    }

    private static func lanePurpose(_ stage: AgentStage?) -> FloorWorkerLane.Purpose {
        switch stage {
        case .scout: return .answer // scout distills the source; projects as an answer lane
        case .answer: return .answer
        case .review: return .review
        case .plan: return .lead
        case .none: return .answer
        }
    }

    private static func workerLanes(for run: TeamRun) -> [FloorWorkerLane] {
        run.workers.map { worker in
            let answer = run.workerAnswer(workerId: worker.id)
            let createdAt = answer?.result.timing.finishedAt ?? answer?.result.timing.startedAt ?? run.createdAt
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
                status: (answer?.result.status ?? .queued).rawValue,
                startedAt: answer?.result.timing.startedAt,
                finishedAt: answer?.result.timing.finishedAt,
                durationMs: answer?.result.timing.durationMs,
                exitCode: answer?.result.exitCode,
                summary: excerpt(answer?.output),
                artifactRefs: refs,
                promptArtifactRef: promptRef,
                error: answer?.result.errorReason
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
                code: "AGENT_FAILED",
                ruleId: "agent.failed",
                message: a.result.errorReason ?? "worker \(a.memberId) failed",
                requiresManual: false,
                retryable: true,
                agentId: a.memberId
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
        var refs = stage.map { s in stageArtifacts.filter { $0.stageId == s.id } } ?? []

        // F-S03: a Signal run carries a typed insight when the writer emitted a
        // parseable structured block; surface it + an insightJSON artifact ref.
        let kind = returnKind(for: run.outputKind)
        let insight = kind == .insight ? SignalInsightParser.parse(fromWriterOutput: markdown) : nil
        if insight != nil {
            refs.append(RunArtifactRef(
                id: "\(run.id)_insight", runId: run.id, kind: .insightJSON, title: "Signal insight",
                relativePath: "return/insight.json", mimeType: "application/json",
                createdAt: stage?.finishedAt ?? run.createdAt))
        }

        return FloorReturn(
            kind: kind,
            status: status(for: run.status).rawValue,
            title: title,
            summaryMarkdown: markdown,
            producedByAgentId: leadWorkerId,
            stageId: stage?.id,
            artifactRefs: refs,
            insight: insight
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
        case .bugPacket, .securityRegister, .specReview: return .audit
        case .designBoard, .polishBoard, .copyBoard: return .board
        case .none: return .plan
        }
    }

    private static func baseNextActions(for run: TeamRun) -> [FloorNextAction] {
        var actions: [FloorNextAction] = []
        let hasReturn = run.plan != nil || run.latestStage(.board) != nil

        if hasReturn {
            actions.append(FloorNextAction(id: "copy_return", kind: .copyReturn, label: "Copy return"))
            actions.append(FloorNextAction(id: "save_pending", kind: .savePending, label: "Save to Pending"))
            // Route the result onward to another team (still shows what will run).
            actions.append(FloorNextAction(id: "send_team", kind: .sendTeam, label: "Send to another team"))
        }

        // Signal insight outcomes route to Copy/Code/Design and external monitoring
        // (the Signal Intake next actions). All non-mutating.
        if run.outputKind == .insight {
            actions.append(FloorNextAction(id: "draft_copy", kind: .draftCopy, label: "Draft copy"))
            actions.append(FloorNextAction(id: "create_code_proposal", kind: .createCodeProposal, label: "Create code proposal"))
            actions.append(FloorNextAction(id: "create_design_brief", kind: .createDesignBrief, label: "Create design brief"))
            actions.append(FloorNextAction(id: "monitor_externally", kind: .monitorExternally, label: "Monitor externally"))
        }

        if hasReturn {
            actions.append(FloorNextAction(id: "ignore", kind: .ignore, label: "Ignore"))
        }

        actions.append(FloorNextAction(id: "show_run", kind: .showRun, label: "Open run",
                                       command: "alln show \(run.id) --json"))
        actions.append(FloorNextAction(id: "show_history", kind: .showHistory, label: "Search history",
                                       command: "alln history --json"))
        return actions
    }

    /// Derive the converge timeline from sourced timestamps only (F-S04). Never
    /// invents a timestamp: a worker/stage with no recorded time contributes no
    /// event. Sorted chronologically.
    private static func timeline(for run: TeamRun) -> [FloorTimelineEvent] {
        var events: [FloorTimelineEvent] = []
        func add(_ kind: FloorTimelineEvent.Kind, _ at: Date?, workerId: String? = nil,
                 stageId: String? = nil, status: String? = nil) {
            guard let at else { return }
            let key = [kind.rawValue, workerId, stageId].compactMap { $0 }.joined(separator: "_")
            events.append(FloorTimelineEvent(id: "\(run.id)_\(key)", runId: run.id, kind: kind,
                                             at: at, workerId: workerId, stageId: stageId, status: status))
        }

        add(.runQueued, run.createdAt)
        // Run started = the first worker that actually began (a real timestamp).
        add(.runStarted, run.answers.compactMap(\.result.timing.startedAt).min())

        for a in run.answers {
            add(.workerStarted, a.result.timing.startedAt, workerId: a.memberId)
            let returned: FloorTimelineEvent.Kind = (a.result.status == .failed || a.result.status == .timedOut) ? .workerFailed : .workerReturned
            add(returned, a.result.timing.finishedAt, workerId: a.memberId, status: a.result.status.rawValue)
        }

        for stage in run.stages {
            // The lead synthesis (plan / final spec) reads as synthesis; other
            // stages read as generic stage events.
            let isSynthesis = stage.purpose == .plan || stage.purpose == .finalSpec
            add(isSynthesis ? .synthesisStarted : .stageStarted, stage.startedAt, stageId: stage.id, status: stage.status.rawValue)
            add(isSynthesis ? .synthesisFinished : .stageFinished, stage.finishedAt, stageId: stage.id, status: stage.status.rawValue)
        }

        // Run finished = the last observed terminal timestamp (never invented).
        if run.status.isTerminal {
            let lastTimes = run.answers.compactMap(\.result.timing.finishedAt) + run.stages.compactMap(\.finishedAt)
            add(.runFinished, lastTimes.max())
        }

        return events.sorted { $0.at < $1.at }
    }

    private static func excerpt(_ text: String?, max: Int = 280) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.count <= max { return text }
        return String(text.prefix(max)) + "…"
    }
}
