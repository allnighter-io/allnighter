import Foundation
import AgentOSTeam

/// Projects the internal `TeamRun` persistence model into the public
/// `TeamRunJSON` contract (docs/archive/phases/CLI_Implementation_Contract.md
/// §TeamRunJSON). The internal model may evolve; this mapper is the single seam
/// that keeps the public contract stable. `alln team --json`, `alln show --json`,
/// and the GUI/MCP/iOS presenters all read the mapper's output — never the raw
/// internal model.
public enum TeamRunJSONMapper {
    /// CLI-supplied context the internal `TeamRun` does not carry.
    ///
    /// ORS-S03c: journal paths stay on disk as audit internals only — they are
    /// never a public TeamRunJSON field (no filesystem escape hatch).
    public struct Context: Sendable {
        public var promptSource: TeamRunJSON.PromptSource
        public var lane: String?
        public var type: String?
        public var effort: String?
        public var reproduceCommand: String?
        public var includeWorkerPromptSnapshots: Bool
        /// Run folder for resolving design image absolute paths.
        public var runDirectory: URL?
        /// Durable delivery receipt supplied by the read-side owner for terminal runs.
        public var pmTurn: PMTurnJSON?
        /// Status/result-level notes associated with the delivery receipt.
        public var pmTurnNotes: [String]
        /// Absolute path to written `artifact/index.html` (CLI write boundary).
        /// Mapper never writes HTML — callers that own the run directory materialize it.
        public var artifactPath: String?
        /// Ownership fact from the read path that reconciles process identity.
        /// Mapper never probes processes — default `.unknown` until a caller supplies it.
        public var ownerState: TeamRunJSON.Observation.OwnerState
        public init(
            promptSource: TeamRunJSON.PromptSource = .init(kind: .positional),
            lane: String? = nil, type: String? = nil, effort: String? = nil,
            reproduceCommand: String? = nil,
            includeWorkerPromptSnapshots: Bool = false,
            runDirectory: URL? = nil,
            pmTurn: PMTurnJSON? = nil,
            pmTurnNotes: [String] = [],
            artifactPath: String? = nil,
            ownerState: TeamRunJSON.Observation.OwnerState = .unknown
        ) {
            self.promptSource = promptSource; self.lane = lane; self.type = type
            self.effort = effort
            self.reproduceCommand = reproduceCommand
            self.includeWorkerPromptSnapshots = includeWorkerPromptSnapshots
            self.runDirectory = runDirectory
            self.pmTurn = pmTurn
            self.pmTurnNotes = pmTurnNotes
            self.artifactPath = artifactPath
            self.ownerState = ownerState
        }
    }

    public static func map(
        _ run: TeamRun,
        models: [Model],
        manifests: [DriverManifest],
        context: Context
    ) -> TeamRunJSON {
        let modelById = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let manifestById = Dictionary(manifests.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func modelName(_ id: String) -> String { modelById[id]?.displayName ?? id }
        func sourceId(_ modelId: String) -> String { modelById[modelId]?.driverId ?? "" }

        let planStage = run.latestStage(.plan)

        let workers = run.workers.map { w in
            TeamRunJSON.AgentInfo(
                id: w.id, skillId: w.skillId, skillName: w.skillName ?? w.label ?? w.skillId,
                resolvedAgentPromptSnapshot: context.includeWorkerPromptSnapshots ? w.resolvedWorkerPromptSnapshot : nil,
                modelId: w.modelId, modelName: modelName(w.modelId), sourceId: sourceId(w.modelId),
                purpose: workerPurpose(w.purpose), instanceIndex: w.instanceIndex
            )
        }

        let answers = run.answers.map { a in
            let outputAbsolute: String? = {
                guard let output = a.output, let dir = context.runDirectory,
                      RunImagePathResolver.isImagePath(output) else { return nil }
                return RunImagePathResolver.absolutePath(runDirectory: dir, relativePath: output)
            }()
            let agentId = run.workers.first(where: { $0.id == a.memberId })?.agentId
            return TeamRunJSON.AnswerInfo(
                agentId: agentId ?? a.memberId, modelId: a.modelId, status: mapWorker(a.result.status),
                queueMs: a.queueMs, ttftMs: a.result.timing.ttftMs,
                durationMs: a.result.timing.durationMs, markdown: a.output,
                outputAbsolutePath: outputAbsolute,
                error: errorEnvelope(for: a, runId: run.id),
                usage: ObservedUsagePresentation.wireUsage(a.result.reportedTokenUsage)
            )
        }

        let designBoard = mapDesignBoard(run, runDirectory: context.runDirectory)

        let stages = run.stages.compactMap { mapStage($0) }

        // Emit a plan only when one was actually produced (stage done → `run.plan`
        // is the markdown). A failed/absent plan is null here and remains visible
        // as a stage in `stages`. Canonical markdown moves to `answer` below.
        var plan: TeamRunJSON.Plan? = {
            guard let stage = planStage, let markdown = run.plan else { return nil }
            return TeamRunJSON.Plan(
                status: .done, writerAgentId: stage.producedByAgentId,
                stageId: stage.id, markdown: markdown
            )
        }()

        let ran = run.answers.filter { $0.result.status != .skipped }.count
        let planDone = planStage?.status == .done
        let usage = TeamRunJSON.Usage(cliCalls: ran + (planDone ? 1 : 0))

        let started = run.answers.compactMap(\.result.timing.startedAt).min()
        let completed = run.status.isTerminal ? run.answers.compactMap(\.result.timing.finishedAt).max() : nil

        // RLR-S02a — project the durable FIFO blocker onto the wire (never wired before).
        // Only for non-terminal runs; terminal transitions clear the blocker in the journal.
        let blockerInfo: TeamRunJSON.BlockerJSON? = {
            guard !run.status.isTerminal, let b = run.blocker else { return nil }
            return TeamRunJSON.BlockerJSON(
                resource: b.resource.rawValue,
                scopeRoot: b.scopeRoot,
                holderId: b.holderId,
                // RLR-L4: P0 public holderKind is `run`; never leak the internal site kind.
                holderKind: b.holderKind.map { _ in "run" },
                ticketPosition: b.ticketPosition,
                holderAcquiredAt: iso(b.holderAcquiredAt),
                // Derived at projection, never stored (RLR-L4).
                heldSinceSeconds: b.holderAcquiredAt.map { max(0, Date().timeIntervalSince($0)) },
                holderDeadlineAt: nil,
                quotaScope: b.quotaScope,
                wakeAfter: iso(b.wakeAfter),
                capacityObservation: b.capacityObservation.map(capacityJSON))
        }()

        let attempts = run.attempts.map { attempt in
            TeamRunJSON.AttemptJSON(
                attemptNumber: attempt.attemptNumber,
                requestedSourceId: attempt.requestedSourceId,
                requestedModelId: attempt.requestedModelId,
                resolvedSourceId: attempt.resolvedSourceId,
                resolvedModelId: attempt.resolvedModelId,
                startedAt: isoString(attempt.startedAt),
                endedAt: iso(attempt.endedAt),
                capacityObservation: attempt.capacityObservation.map(capacityJSON),
                vendorSessionId: attempt.vendorSessionId,
                selectionOrigin: attempt.selectionOrigin,
                substitutionOfAttempt: attempt.substitutionOfAttempt,
                terminalStatus: attempt.terminalStatus.map(mapWorker),
                reason: attempt.reason,
                diagnosticSnippet: attempt.diagnosticSnippet
            )
        }

        // Prefer the run's own catalog facts (self-describing); fall back to
        // caller-supplied context for legacy runs that did not record them.
        let workerModelId = RunIdentity.primaryWorkerModelId(run)
        let runStatus = mapRun(run.status)
        let info = TeamRunJSON.RunInfo(
            id: run.id, status: runStatus, origin: mapOrigin(run.origin),
            originAgent: run.originAgent,
            lane: run.lane?.rawValue ?? context.lane,
            type: run.type ?? context.type,
            effort: run.effort?.rawValue ?? context.effort,
            prompt: run.prompt, promptSource: context.promptSource,
            createdAt: isoString(run.createdAt), startedAt: iso(started), completedAt: iso(completed),
            threadId: run.threadId, teamPresetId: run.presetId,
            teamDisplayName: run.teamDisplayName, outputKind: run.outputKind?.rawValue,
            modelId: workerModelId,
            writePolicy: RunIdentity.writePolicyLabel(mutating: run.mutating),
            identitySummary: RunIdentity.summary(
                modelId: workerModelId, lane: run.lane, mutating: run.mutating,
                laneContextOnly: run.laneContextOnly == true),
            planWriterAgentId: plan?.writerAgentId, reproduceCommand: context.reproduceCommand,
            endReason: run.endReason?.rawValue, blocker: blockerInfo, attempts: attempts
        )

        var runWarnings = run.warnings.map { TeamRunJSON.Warning(message: $0) }
        // A run whose seats all failed to start inside a sandboxing host must say
        // why, in plain language, instead of returning an unexplained empty run.
        // Keyed off the observed failure, never the environment alone.
        if let advice = HostSandboxAdvice.detect(
            workerFailureText: run.answers.compactMap { $0.result.errorReason },
            prompt: run.prompt,
            projectReference: run.repoRoot,
            teamId: run.presetId,
            capacityAuthRequired: run.answers.contains {
                $0.result.capacityObservation?.kind == .authRequired
            }
        ) {
            runWarnings.insert(
                TeamRunJSON.Warning(code: HostSandboxAdvice.code, message: advice.warningMessage),
                at: 0)
        }

        var projectedAnswers = answers
        let answer = deriveAnswer(
            runStatus: runStatus,
            outputKind: run.outputKind?.rawValue,
            plan: &plan,
            answers: &projectedAnswers,
            designBoard: designBoard
        )

        // ORS-S01 — three-field observation, projected once.
        // activityMode from resolved driver canStream (never from output arrival).
        // ownerState from caller context (never process-probed here).
        // lastActivityAt: clock fact from TeamRun, projected as ISO8601 string
        // exactly like RunInfo.createdAt (never age/staleness arithmetic; never Date).
        let activityMode: TeamRunJSON.Observation.ActivityMode = {
            let driverId = workerModelId.flatMap { modelById[$0]?.driverId }
                ?? run.executionSourceId
            guard let driverId, let manifest = manifestById[driverId] else {
                return .unknown
            }
            return manifest.canStream ? .incremental : .terminalOnly
        }()
        let observation = TeamRunJSON.Observation(
            ownerState: context.ownerState,
            activityMode: activityMode,
            lastActivityAt: iso(run.lastActivityAt)
        )

        return TeamRunJSON(
            schemaVersion: 2,
            contractVersion: ContractRegistry.contractVersion,
            teamRun: info, agents: workers, answers: projectedAnswers,
            answer: answer,
            pmTurn: context.pmTurn,
            notes: context.pmTurnNotes,
            designBoard: designBoard,
            repoDelta: run.mutating ? run.repoDelta : nil,
            researchGitObservation: run.mutating ? nil : run.researchGitObservation,
            outcome: run.status.isTerminal ? mapOutcome(run) : nil,
            stages: stages, plan: plan, usage: usage,
            warnings: runWarnings, errors: runErrors(run),
            nextActions: terminalArtifactNextActions(
                for: run,
                answerContent: !(answer?.markdown ?? "").isEmpty
                    || projectedAnswers.contains { !($0.markdown ?? "").isEmpty }
            ),
            artifact: artifactRef(for: run, path: context.artifactPath),
            audit: .init(traceId: "trace_\(run.id)"),
            observation: observation
        )
    }

    /// Top-level finish for terminal runs. `path` comes from the write boundary
    /// (never from this pure map). `openCommand` always when projectable.
    public static func artifactRef(for run: TeamRun, path: String? = nil) -> TeamRunJSON.Artifact? {
        guard ArtifactProjector.canProject(run) else { return nil }
        return TeamRunJSON.Artifact(
            path: path,
            openCommand: "alln artifact show \(run.id)"
        )
    }

    /// Deterministic canonical-answer derivation (archived Alln_Sharpening § Canonical answer).
    /// Mutates `plan` / `answers` so markdown is not duplicated (Law 2).
    public static func deriveAnswer(
        runStatus: TeamRunJSON.Status,
        outputKind: String?,
        plan: inout TeamRunJSON.Plan?,
        answers: inout [TeamRunJSON.AnswerInfo],
        designBoard: TeamRunJSON.DesignBoard?
    ) -> TeamRunJSON.Answer? {
        // VSI-S05: hoist a non-empty single-worker partial even when the run did
        // not succeed. Consumers must not assume `answer != null` ⇒ `status == done`.
        if runStatus != .done {
            return hoistSingleWorkerPartial(
                runStatus: runStatus,
                outputKind: outputKind,
                answers: &answers
            )
        }

        // 1. Completed synthesized plan → answer from plan; plan keeps provenance only.
        if var donePlan = plan, donePlan.status == .done,
           let markdown = donePlan.markdown, !markdown.isEmpty {
            donePlan.markdown = nil
            plan = donePlan
            return TeamRunJSON.Answer(
                status: .done,
                outputKind: outputKind,
                markdown: markdown,
                source: .init(
                    kind: .plan,
                    agentId: donePlan.writerAgentId,
                    modelId: answers.first { $0.agentId == donePlan.writerAgentId }?.modelId,
                    stageId: donePlan.stageId
                )
            )
        }

        // 2. Successful one-worker → answer from that worker; row keeps status/model/timing.
        let seats = answers.filter { $0.status != .skipped }
        if seats.count == 1, let only = seats.first, only.status == .done,
           let markdown = only.markdown, !markdown.isEmpty,
           let idx = answers.firstIndex(where: { $0.agentId == only.agentId }) {
            answers[idx].markdown = nil
            return TeamRunJSON.Answer(
                status: .done,
                outputKind: outputKind,
                markdown: markdown,
                source: .init(
                    kind: .worker,
                    agentId: only.agentId,
                    modelId: only.modelId
                )
            )
        }

        // 3. Typed board → typedResultField + optional lead summary; payload stays typed.
        if designBoard != nil {
            let leadSummary = plan?.markdown.flatMap { $0.isEmpty ? nil : $0 }
            if leadSummary != nil, var p = plan {
                p.markdown = nil
                plan = p
            }
            return TeamRunJSON.Answer(
                status: .done,
                outputKind: outputKind,
                markdown: leadSummary,
                source: .init(kind: .typed),
                typedResultField: "designBoard"
            )
        }

        // 4. Partial multi-seat without synthesis → answer null; keep seat markdowns.
        return nil
    }

    /// VSI-S05 — non-success single-worker hoist. Live `.running` stays null so
    /// mid-stream show does not invent a terminal answer; parked (`.queued`) and
    /// failed/killed/timed-out/interrupted runs surface the durable partial.
    private static func hoistSingleWorkerPartial(
        runStatus: TeamRunJSON.Status,
        outputKind: String?,
        answers: inout [TeamRunJSON.AnswerInfo]
    ) -> TeamRunJSON.Answer? {
        switch runStatus {
        case .failed, .timedOut, .cancelled, .interrupted, .queued:
            break
        case .running, .done, .skipped:
            return nil
        }
        let seats = answers.filter { $0.status != .skipped }
        guard seats.count == 1, let only = seats.first,
              let markdown = only.markdown, !markdown.isEmpty,
              let idx = answers.firstIndex(where: { $0.agentId == only.agentId })
        else { return nil }
        answers[idx].markdown = nil
        return TeamRunJSON.Answer(
            status: runStatus,
            outputKind: outputKind,
            markdown: markdown,
            source: .init(
                kind: .worker,
                agentId: only.agentId,
                modelId: only.modelId
            )
        )
    }

    /// Agent terminal states → mechanical outcome status (never a correctness verdict).
    static func mapOutcomeStatus(_ run: TeamRun) -> TeamRunJSON.Outcome.Status {
        let answers = run.answers.filter { $0.result.status != .skipped }
        guard !answers.isEmpty else { return .failed }
        let doneCount = answers.filter { $0.result.status == .done }.count
        if doneCount == answers.count { return .completed }
        if doneCount > 0 { return .partial }
        if answers.contains(where: { $0.result.status == .timedOut }) { return .timedOut }
        return .failed
    }

    static func mapOutcome(_ run: TeamRun) -> TeamRunJSON.Outcome {
        let commitMatched = run.requestedCommitMessage.flatMap {
            CommitMessageFidelity.matched(requested: $0, delta: run.repoDelta)
        }
        let proof: TeamRunJSON.Outcome.Proof? = run.proofResult.map {
            TeamRunJSON.Outcome.Proof(
                command: $0.command, exitCode: $0.exitCode, passed: $0.passed, outputTail: $0.outputTail)
        }
        // OUR-S01: single non-skipped seat only — never first-answer copy / multi-seat sum.
        let usage = ObservedUsagePresentation.wireUsage(
            ObservedUsagePresentation.singleSeatUsage(for: run)
        )
        let wallMs = observedWallMs(run)
        let outcomeStatus = mapOutcomeStatus(run)
        let changed = run.repoDelta?.changed == true
        // Only meaningful for a mutating run that claims success: a read-only
        // run producing no diff is correct, not a mismatch.
        let completedWithoutChanges: Bool? = {
            guard run.mutating else { return nil }
            switch outcomeStatus {
            case .completed, .partial: return !changed
            case .failed, .timedOut: return nil
            }
        }()
        return TeamRunJSON.Outcome(
            status: outcomeStatus,
            committed: changed,
            headline: outcomeHeadline(run, status: outcomeStatus, wallMs: wallMs),
            completedWithoutChanges: completedWithoutChanges,
            commitMessageMatched: commitMatched,
            proof: proof,
            usage: usage,
            timing: .init(wallMs: wallMs))
    }

    /// Observed wall ms: run `createdAt` → latest worker `finishedAt`. Null when unfinished.
    static func observedWallMs(_ run: TeamRun) -> Int? {
        guard let finished = run.answers.compactMap(\.result.timing.finishedAt).max() else {
            return nil
        }
        return max(0, Int(finished.timeIntervalSince(run.createdAt) * 1000))
    }

    // MARK: - Enum mappings

    /// Internal run lifecycle → the closed public set. `partial` is a finished run
    /// with some failed workers (shown in answers), so it maps to `done`.
    static func mapRun(_ s: RunStatus) -> TeamRunJSON.Status {
        switch s {
        case .draft, .queued: return .queued
        case .running, .fanningOut, .answersIn, .planning, .reviewing, .finalizing: return .running
        case .complete, .partial, .done: return .done
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .failed: return .failed
        case .interrupted: return .interrupted
        }
    }

    static func mapWorker(_ s: WorkerAnswerStatus) -> TeamRunJSON.Status {
        switch s {
        case .queued: return .queued
        case .running: return .running
        case .done: return .done
        case .failed: return .failed
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .skipped: return .skipped
        }
    }

    static func mapStage(status s: StageStatus) -> TeamRunJSON.Status {
        switch s {
        case .queued: return .queued
        case .running: return .running
        case .done, .reused: return .done
        case .failed: return .failed
        case .timedOut: return .timedOut
        case .skipped: return .skipped
        }
    }

    /// Agent stage → public worker purpose. Legacy runs (nil) are answer workers.
    static func workerPurpose(_ stage: AgentStage?) -> TeamRunJSON.WorkerPurpose {
        switch stage {
        case .review: return .review
        case .plan: return .plan
        case .scout, .answer, nil: return .answer // scout projects as an answer worker
        }
    }

    static func mapOrigin(_ o: RunOrigin) -> TeamRunJSON.Origin {
        switch o {
        case .cli: return .cli
        case .gui: return .gui
        case .mcp: return .mcp
        case .http: return .localApi
        case .ios: return .ios
        }
    }

    /// Only `analysis`/`plan`/`review` are part of the public M1 stage set; RB
    /// stages (finalSpec/board) are filtered out.
    static func mapStage(_ stage: StageOutput) -> TeamRunJSON.StageInfo? {
        let purpose: TeamRunJSON.StagePurpose
        switch stage.purpose {
        case .analysis: purpose = .analysis
        case .plan: purpose = .plan
        case .review: purpose = .review
        default: return nil
        }
        return TeamRunJSON.StageInfo(
            id: stage.id, purpose: purpose, status: mapStage(status: stage.status),
            producedByAgentId: stage.producedByAgentId, promptProfileId: stage.promptProfileId
        )
    }

    private static func errorEnvelope(for a: TeamAnswer, runId: String) -> ErrorEnvelope? {
        guard a.result.status == .failed || a.result.status == .timedOut else { return nil }
        return ErrorEnvelope(
            code: a.result.status == .timedOut ? "TEAM_RUN_TIMEOUT" : "AGENT_FAILED",
            message: a.result.errorReason ?? "worker did not produce an answer",
            requiresManual: false, retryable: true, runId: runId, agentId: a.memberId
        )
    }

    /// RRT-S03 — `outcome.headline` used to be byte-identical to
    /// `teamRun.identitySummary`: the field named `headline` printed *who ran*
    /// ("model model_gpt_sol · lane code · readOnly") and never *what happened*.
    /// On a read-only judgment run nothing else was appended, so the reader got
    /// identity and nothing else, while the verdict sat 40 lines deep in 14 KB
    /// of markdown.
    ///
    /// Lead with what happened, then keep the existing repo-delta / proof tail.
    /// Adds no field: the verdict comes from `LeadCallParser`, which already
    /// ships and which `ArtifactProjector` already trusts for the HTML artifact.
    static func outcomeHeadline(
        _ run: TeamRun, status: TeamRunJSON.Outcome.Status, wallMs: Int?
    ) -> String {
        var lead: [String] = []
        if let call = leadCall(in: run),
           let verdict = call.status?.trimmingCharacters(in: .whitespacesAndNewlines),
           !verdict.isEmpty {
            lead.append(verdict)
            if let title = call.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty { lead.append(title) }
        }
        // A true `partial` must name its subject: which seats did not deliver.
        // Without this the reader takes one bare word as a verdict on the run.
        if status == .partial {
            let ran = run.answers.filter { $0.result.status != .skipped }
            let done = ran.filter { $0.result.status == .done }.count
            lead.append("\(done) of \(ran.count) seats delivered")
        }
        let identity = RunIdentity.outcomeHeadline(run, wallMs: wallMs)
        guard !lead.isEmpty else { return identity }
        return (lead + [identity]).joined(separator: " · ")
    }

    /// First parseable lead-call block in the run's durable text. The synthesis
    /// (`run.plan`) wins over a single seat's answer, matching how `answer` is
    /// projected.
    private static func leadCall(in run: TeamRun) -> LeadCall? {
        if let call = LeadCallParser.parse(from: run.plan), call.status != nil { return call }
        for answer in run.answers {
            if let call = LeadCallParser.parse(from: answer.output), call.status != nil { return call }
        }
        return nil
    }

    /// RRT-S04 — top-level `errors` used to be a hardcoded `[]`, so no run ever
    /// reported a failure reason at the top level even when the reason was
    /// already present in `answers[].error`, `pmTurn.notes`, and
    /// `teamRun.attempts[]`. A caller reading the field named `errors` on a
    /// failed run learned nothing.
    ///
    /// Collect the per-answer envelopes that already exist. When a run failed
    /// before producing any answer envelope, fall back to the last attempt that
    /// recorded a reason so the run still says why it failed. Adds no field and
    /// no new classification — `code` stays whatever `errorEnvelope` derived.
    static func runErrors(_ run: TeamRun) -> [ErrorEnvelope] {
        let answerErrors = run.answers.compactMap { errorEnvelope(for: $0, runId: run.id) }
        guard answerErrors.isEmpty else { return answerErrors }
        guard let attempt = run.attempts.last(where: { !($0.reason ?? "").isEmpty }),
              let reason = attempt.reason
        else { return [] }
        return [ErrorEnvelope(
            code: "AGENT_FAILED", message: reason,
            requiresManual: false, retryable: true, runId: run.id
        )]
    }

    private static func iso(_ date: Date?) -> String? {
        guard let date else { return nil }
        return isoString(date)
    }
    private static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private static func capacityJSON(_ observation: CapacityObservation) -> CapacityObservationJSON {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return CapacityObservationJSONMapper.map(observation, iso: formatter)
    }

    static func mapDesignBoard(_ run: TeamRun, runDirectory: URL?) -> TeamRunJSON.DesignBoard? {
        let isDesign = run.lane == .design || run.outputKind == .designBoard
        guard isDesign, let board = run.latestStage(.board)?.payload?.board else { return nil }
        let screenshotAbsolute = board.screenshotPath.flatMap { rel in
            runDirectory.flatMap { RunImagePathResolver.absolutePath(runDirectory: $0, relativePath: rel) }
        }
        let options = board.options.map { opt in
            TeamRunJSON.DesignBoardOption(
                agentId: opt.agentId,
                modelId: opt.modelId,
                persona: opt.persona,
                imagePath: opt.imagePath,
                absolutePath: opt.imagePath.flatMap { rel in
                    runDirectory.flatMap { RunImagePathResolver.absolutePath(runDirectory: $0, relativePath: rel) }
                },
                status: mapStage(status: opt.status),
                failureReason: opt.failureReason,
                sessionId: opt.sessionId
            )
        }
        let chosen = board.chosen.map { c in
            TeamRunJSON.DesignBoardChosen(
                agentId: c.agentId,
                persona: c.persona,
                chosenAt: c.chosenAt.map(isoString)
            )
        }
        return TeamRunJSON.DesignBoard(
            targetShape: board.targetShape.rawValue,
            screenshotPath: board.screenshotPath,
            screenshotAbsolutePath: screenshotAbsolute,
            options: options,
            chosen: chosen
        )
    }

    /// Terminal runs lead with Open artifact — that is the polished finish, not
    /// `show` / markdown export. Prefer top-level `artifact` for agents.
    /// In-flight runs with answer text lead with `showAnswer` instead — the
    /// artifact does not exist yet, and work already in the record must stay
    /// retrievable by a documented command, never written off as lost.
    /// Non-success terminals (killed / failed / timed out) keep the artifact
    /// lead but also surface `showAnswer` when the record holds text — the
    /// polished path is often null and the durable body is the recovery.
    static func terminalArtifactNextActions(
        for run: TeamRun,
        answerContent: Bool = false
    ) -> [TeamRunJSON.NextAction] {
        var actions: [TeamRunJSON.NextAction] = []
        if run.status.isTerminal {
            actions.append(.init(
                kind: .showArtifact,
                command: "alln artifact show \(run.id)",
                label: "Open team artifact"
            ))
            if answerContent && run.status.needsAnswerRecoveryHint {
                actions.append(.init(
                    kind: .showAnswer,
                    command: "alln show \(run.id) --answer",
                    label: "Read the answer text"
                ))
            }
        } else if answerContent {
            actions.append(.init(
                kind: .showAnswer,
                command: "alln show \(run.id) --answer",
                label: "Read the answer text"
            ))
        }
        actions.append(.init(kind: .showRun, command: "alln show \(run.id)", label: "Show run"))
        actions.append(.init(
            kind: .export,
            command: "alln export \(run.id) --format md",
            label: "Export markdown"
        ))
        return actions
    }

    /// Write `artifact/index.html` under the run journal when projectable.
    /// Pure map callers must not use this — CLI / presenters only (avoids
    /// recursion through `ArtifactProjector` → `TeamRunJSONMapper.map`).
    public static func materializeArtifactPath(
        for run: TeamRun,
        runDirectory: URL,
        reproduceCommand: String,
        models: [Model] = [],
        manifests: [DriverManifest] = []
    ) -> String? {
        guard ArtifactProjector.canProject(run) else { return nil }
        let context = ArtifactProjector.Context(models: models, manifests: manifests)
        return try? ArtifactWriter.writeHTML(
            run: run,
            runDirectory: runDirectory,
            reproduceCommand: reproduceCommand,
            context: context
        ).path
    }

}
