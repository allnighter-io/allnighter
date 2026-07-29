import Foundation

/// `TeamRunJSON` — the first public machine contract for a team run
/// (docs/archive/phases/CLI_Implementation_Contract.md §TeamRunJSON).
///
/// This is the shared shape that `alln --json`, the Mac/iOS presenters, and MCP
/// tool results all project from. It is intentionally **separate from the
/// internal persistence model** (`TeamRun`): the internal model may evolve, but
/// this public contract is versioned via `schemaVersion`/`contractVersion`.
///
/// Sub-types are nested so the public surface reads as one contract and does not
/// collide with the internal `Model`/`Agent`/`TeamRun`/`StageOutput` types.
public struct TeamRunJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var teamRun: RunInfo
    public var agents: [AgentInfo]
    public var answers: [AnswerInfo]
    /// Canonical result text. Always serialized (JSON `null` while non-terminal or
    /// when no canonical result exists). See `TeamRunJSONMapper.deriveAnswer`.
    public var answer: Answer?
    public var designBoard: DesignBoard?
    public var repoDelta: RepoDelta?
    /// CR-S02 — bounded pre/post Git observation for a research (read-only) run.
    /// Present only on research runs (mutating runs carry `repoDelta`). `changed == true`
    /// surfaces a research-write violation; Allnighter never resets the tree.
    public var researchGitObservation: ResearchGitObservation?
    /// Mechanical run verdict from worker terminal states + repo delta — never a correctness claim.
    public var outcome: Outcome?
    public var stages: [StageInfo]
    public var plan: Plan?
    public var usage: Usage
    public var warnings: [Warning]
    public var errors: [ErrorEnvelope]
    public var nextActions: [NextAction]
    public var audit: Audit

    public init(
        schemaVersion: Int = 2,
        contractVersion: String,
        teamRun: RunInfo,
        agents: [AgentInfo],
        answers: [AnswerInfo],
        answer: Answer? = nil,
        designBoard: DesignBoard? = nil,
        repoDelta: RepoDelta? = nil,
        researchGitObservation: ResearchGitObservation? = nil,
        outcome: Outcome? = nil,
        stages: [StageInfo],
        plan: Plan?,
        usage: Usage,
        warnings: [Warning] = [],
        errors: [ErrorEnvelope] = [],
        nextActions: [NextAction] = [],
        audit: Audit
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.teamRun = teamRun
        self.agents = agents
        self.answers = answers
        self.answer = answer
        self.designBoard = designBoard
        self.repoDelta = repoDelta
        self.researchGitObservation = researchGitObservation
        self.outcome = outcome
        self.stages = stages
        self.plan = plan
        self.usage = usage
        self.warnings = warnings
        self.errors = errors
        self.nextActions = nextActions
        self.audit = audit
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, contractVersion, teamRun, agents, answers, answer
        case designBoard, repoDelta, researchGitObservation, outcome, stages, plan, usage, warnings, errors
        case nextActions, audit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        contractVersion = try c.decode(String.self, forKey: .contractVersion)
        teamRun = try c.decode(RunInfo.self, forKey: .teamRun)
        agents = try c.decode([AgentInfo].self, forKey: .agents)
        answers = try c.decode([AnswerInfo].self, forKey: .answers)
        // Required on the wire (null while non-terminal / no canonical result).
        answer = try c.decode(Answer?.self, forKey: .answer)
        designBoard = try c.decodeIfPresent(DesignBoard.self, forKey: .designBoard)
        repoDelta = try c.decodeIfPresent(RepoDelta.self, forKey: .repoDelta)
        researchGitObservation = try c.decodeIfPresent(ResearchGitObservation.self, forKey: .researchGitObservation)
        outcome = try c.decodeIfPresent(Outcome.self, forKey: .outcome)
        stages = try c.decode([StageInfo].self, forKey: .stages)
        // Required on the wire (null when no plan stage produced).
        plan = try c.decode(Plan?.self, forKey: .plan)
        usage = try c.decode(Usage.self, forKey: .usage)
        warnings = try c.decode([Warning].self, forKey: .warnings)
        errors = try c.decode([ErrorEnvelope].self, forKey: .errors)
        nextActions = try c.decode([NextAction].self, forKey: .nextActions)
        audit = try c.decode(Audit.self, forKey: .audit)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(contractVersion, forKey: .contractVersion)
        try c.encode(teamRun, forKey: .teamRun)
        try c.encode(agents, forKey: .agents)
        try c.encode(answers, forKey: .answers)
        // Law 2: always serialize `answer` (including JSON null).
        try c.encode(answer, forKey: .answer)
        try c.encodeIfPresent(designBoard, forKey: .designBoard)
        try c.encodeIfPresent(repoDelta, forKey: .repoDelta)
        try c.encodeIfPresent(researchGitObservation, forKey: .researchGitObservation)
        try c.encodeIfPresent(outcome, forKey: .outcome)
        try c.encode(stages, forKey: .stages)
        try c.encode(plan, forKey: .plan)
        try c.encode(usage, forKey: .usage)
        try c.encode(warnings, forKey: .warnings)
        try c.encode(errors, forKey: .errors)
        try c.encode(nextActions, forKey: .nextActions)
        try c.encode(audit, forKey: .audit)
    }

    // MARK: - Closed, shared enums

    /// Closed run/worker/stage status set (contract: "status enums must be closed
    /// and shared"). Note the public word is `done`, not the internal `complete`.
    public enum Status: String, Codable, Sendable {
        case queued, running, done, failed, timedOut, cancelled, skipped, interrupted
    }

    /// Where the run originated. Every transport stamps its own origin.
    public enum Origin: String, Codable, Sendable {
        case cli, gui, mcp, ios, localApi, system
    }

    /// What a worker contributes. Milestone-1 set only.
    public enum WorkerPurpose: String, Codable, Sendable {
        case answer, plan, review
    }

    /// Reduce/stage purpose.
    public enum StagePurpose: String, Codable, Sendable {
        case analysis, plan, review
    }

    /// Bench-model readiness at run time.
    public enum ModelStatus: String, Codable, Sendable {
        case ready, unavailable, unknown
    }

    // MARK: - teamRun

    public struct RunInfo: Codable, Equatable, Sendable {
        public var id: String
        public var status: Status
        public var origin: Origin
        public var originAgent: String?
        public var lane: String?
        public var type: String?
        public var effort: String?
        public var prompt: String
        public var promptSource: PromptSource
        public var createdAt: String
        public var startedAt: String?
        public var completedAt: String?
        public var threadId: String?
        public var teamPresetId: String?
        public var teamDisplayName: String?
        public var outputKind: String?
        /// Primary model id — the model that ran (or leads identity for multi-worker teams).
        public var modelId: String?
        /// `mutating` or `readOnly` — captured at run start.
        public var writePolicy: String?
        /// Headline identity: `worker <id> · lane <lane> · mutating|readOnly`.
        public var identitySummary: String?
        public var planWriterAgentId: String?
        public var reproduceCommand: String?
        /// Why a terminal run ended (`completed|failed|cancelled|reconciledOrphan|killed|unknown`).
        /// Actor-stamped only — never inferred. Nil while live (PO-S01 v2).
        public var endReason: String?
        /// What a non-terminal run is durably waiting on (RLR-L4). Present only while
        /// blocked (`queued`/`waitingForWriteLock|waitingForVendor`); nil once running
        /// or terminal.
        public var blocker: BlockerJSON?
        /// Append-only sequential attempts for this unified run.
        public var attempts: [AttemptJSON]

        public init(
            id: String, status: Status, origin: Origin, originAgent: String? = nil,
            lane: String? = nil, type: String? = nil, effort: String? = nil,
            prompt: String, promptSource: PromptSource, createdAt: String,
            startedAt: String? = nil, completedAt: String? = nil, threadId: String? = nil,
            teamPresetId: String? = nil, teamDisplayName: String? = nil, outputKind: String? = nil,
            modelId: String? = nil, writePolicy: String? = nil, identitySummary: String? = nil,
            planWriterAgentId: String? = nil, reproduceCommand: String? = nil,
            endReason: String? = nil, blocker: BlockerJSON? = nil,
            attempts: [AttemptJSON] = []
        ) {
            self.id = id; self.status = status; self.origin = origin
            self.originAgent = originAgent; self.lane = lane; self.type = type
            self.effort = effort; self.prompt = prompt; self.promptSource = promptSource
            self.createdAt = createdAt; self.startedAt = startedAt
            self.completedAt = completedAt; self.threadId = threadId
            self.teamPresetId = teamPresetId; self.teamDisplayName = teamDisplayName
            self.outputKind = outputKind; self.modelId = modelId
            self.writePolicy = writePolicy; self.identitySummary = identitySummary
            self.planWriterAgentId = planWriterAgentId
            self.reproduceCommand = reproduceCommand
            self.endReason = endReason
            self.blocker = blocker
            self.attempts = attempts
        }

        private enum CodingKeys: String, CodingKey {
            case id, status, origin, originAgent, lane, type, effort, prompt, promptSource
            case createdAt, startedAt, completedAt, threadId, teamPresetId, teamDisplayName
            case outputKind, modelId, writePolicy, identitySummary, planWriterAgentId
            case reproduceCommand, endReason, blocker, attempts
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            status = try c.decode(Status.self, forKey: .status)
            origin = try c.decode(Origin.self, forKey: .origin)
            originAgent = try c.decodeIfPresent(String.self, forKey: .originAgent)
            lane = try c.decodeIfPresent(String.self, forKey: .lane)
            type = try c.decodeIfPresent(String.self, forKey: .type)
            effort = try c.decodeIfPresent(String.self, forKey: .effort)
            prompt = try c.decode(String.self, forKey: .prompt)
            promptSource = try c.decode(PromptSource.self, forKey: .promptSource)
            createdAt = try c.decode(String.self, forKey: .createdAt)
            startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt)
            completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
            threadId = try c.decodeIfPresent(String.self, forKey: .threadId)
            teamPresetId = try c.decodeIfPresent(String.self, forKey: .teamPresetId)
            teamDisplayName = try c.decodeIfPresent(String.self, forKey: .teamDisplayName)
            outputKind = try c.decodeIfPresent(String.self, forKey: .outputKind)
            modelId = try c.decodeIfPresent(String.self, forKey: .modelId)
            writePolicy = try c.decodeIfPresent(String.self, forKey: .writePolicy)
            identitySummary = try c.decodeIfPresent(String.self, forKey: .identitySummary)
            planWriterAgentId = try c.decodeIfPresent(String.self, forKey: .planWriterAgentId)
            reproduceCommand = try c.decodeIfPresent(String.self, forKey: .reproduceCommand)
            endReason = try c.decodeIfPresent(String.self, forKey: .endReason)
            blocker = try c.decodeIfPresent(BlockerJSON.self, forKey: .blocker)
            attempts = try c.decodeIfPresent([AttemptJSON].self, forKey: .attempts) ?? []
        }
    }

    /// Public projection of `RunBlocker` (RLR-L4). `heldSinceSeconds` is derived at
    /// projection from `holderAcquiredAt` (never stored). `holderKind` is the public
    /// `run` (P0), never the internal site kind. `holderDeadlineAt` is null in P0.
    public struct BlockerJSON: Codable, Equatable, Sendable {
        public var resource: String
        public var scopeRoot: String?
        public var holderId: String?
        public var holderKind: String?
        public var ticketPosition: Int?
        public var holderAcquiredAt: String?
        public var heldSinceSeconds: Double?
        public var holderDeadlineAt: String?
        public var quotaScope: String?
        public var wakeAfter: String?
        public var capacityObservation: CapacityObservationJSON?

        public init(
            resource: String, scopeRoot: String? = nil, holderId: String? = nil,
            holderKind: String? = nil, ticketPosition: Int? = nil,
            holderAcquiredAt: String? = nil, heldSinceSeconds: Double? = nil,
            holderDeadlineAt: String? = nil, quotaScope: String? = nil,
            wakeAfter: String? = nil, capacityObservation: CapacityObservationJSON? = nil
        ) {
            self.resource = resource; self.scopeRoot = scopeRoot
            self.holderId = holderId; self.holderKind = holderKind
            self.ticketPosition = ticketPosition; self.holderAcquiredAt = holderAcquiredAt
            self.heldSinceSeconds = heldSinceSeconds; self.holderDeadlineAt = holderDeadlineAt
            self.quotaScope = quotaScope; self.wakeAfter = wakeAfter
            self.capacityObservation = capacityObservation
        }
    }

    public struct AttemptJSON: Codable, Equatable, Sendable {
        public var attemptNumber: Int
        public var requestedSourceId: String?
        public var requestedModelId: String?
        public var resolvedSourceId: String?
        public var resolvedModelId: String?
        public var startedAt: String
        public var endedAt: String?
        public var capacityObservation: CapacityObservationJSON?
        public var vendorSessionId: String?
        public var selectionOrigin: String?
        public var substitutionOfAttempt: Int?
        public var terminalStatus: Status?
        public var reason: String?
        public var diagnosticSnippet: String?

        public init(
            attemptNumber: Int,
            requestedSourceId: String? = nil,
            requestedModelId: String? = nil,
            resolvedSourceId: String? = nil,
            resolvedModelId: String? = nil,
            startedAt: String,
            endedAt: String? = nil,
            capacityObservation: CapacityObservationJSON? = nil,
            vendorSessionId: String? = nil,
            selectionOrigin: String? = nil,
            substitutionOfAttempt: Int? = nil,
            terminalStatus: Status? = nil,
            reason: String? = nil,
            diagnosticSnippet: String? = nil
        ) {
            self.attemptNumber = attemptNumber
            self.requestedSourceId = requestedSourceId
            self.requestedModelId = requestedModelId
            self.resolvedSourceId = resolvedSourceId
            self.resolvedModelId = resolvedModelId
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.capacityObservation = capacityObservation
            self.vendorSessionId = vendorSessionId
            self.selectionOrigin = selectionOrigin
            self.substitutionOfAttempt = substitutionOfAttempt
            self.terminalStatus = terminalStatus
            self.reason = reason
            self.diagnosticSnippet = diagnosticSnippet
        }
    }

    /// Prompt provenance — never the secret content of a `--file`.
    public struct PromptSource: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case positional, file, stdin }
        public var kind: Kind
        public var path: String?
        public init(kind: Kind, path: String? = nil) { self.kind = kind; self.path = path }
    }

    // MARK: - ModelInfo (DoctorResult) / workers / answer

    /// Bench-model snapshot. Owned by `DoctorResult` / `menu`; not embedded in
    /// run envelopes (catalog-free TeamRunJSON).
    public struct ModelInfo: Codable, Equatable, Sendable {
        public var id: String
        public var displayName: String
        public var sourceId: String
        public var sourceName: String?
        public var status: ModelStatus
        public init(id: String, displayName: String, sourceId: String, sourceName: String? = nil, status: ModelStatus) {
            self.id = id; self.displayName = displayName; self.sourceId = sourceId
            self.sourceName = sourceName; self.status = status
        }
    }

    /// Canonical result path. Markdown appears here exactly once.
    public struct Answer: Codable, Equatable, Sendable {
        public var status: Status
        public var outputKind: String?
        public var markdown: String?
        public var source: Source
        public var typedResultField: String?

        public init(
            status: Status,
            outputKind: String? = nil,
            markdown: String? = nil,
            source: Source,
            typedResultField: String? = nil
        ) {
            self.status = status
            self.outputKind = outputKind
            self.markdown = markdown
            self.source = source
            self.typedResultField = typedResultField
        }

        public struct Source: Codable, Equatable, Sendable {
            public enum Kind: String, Codable, Sendable {
                case plan, worker, typed
            }
            public var kind: Kind
            public var agentId: String?
            public var modelId: String?
            public var stageId: String?

            public init(
                kind: Kind,
                agentId: String? = nil,
                modelId: String? = nil,
                stageId: String? = nil
            ) {
                self.kind = kind
                self.agentId = agentId
                self.modelId = modelId
                self.stageId = stageId
            }
        }
    }

    public struct AgentInfo: Codable, Equatable, Sendable {
        public var id: String
        public var skillId: String?
        public var skillName: String?
        public var resolvedAgentPromptSnapshot: String?
        public var modelId: String
        public var modelName: String
        public var sourceId: String
        public var purpose: WorkerPurpose
        public var instanceIndex: Int
        public init(id: String, skillId: String? = nil, skillName: String? = nil, resolvedAgentPromptSnapshot: String? = nil, modelId: String, modelName: String, sourceId: String, purpose: WorkerPurpose, instanceIndex: Int) {
            self.id = id; self.skillId = skillId; self.skillName = skillName
            self.resolvedAgentPromptSnapshot = resolvedAgentPromptSnapshot
            self.modelId = modelId; self.modelName = modelName; self.sourceId = sourceId
            self.purpose = purpose; self.instanceIndex = instanceIndex
        }
    }

    /// One answer or failure per answer worker. A failed worker is shown failed,
    /// never hidden (`error` carries the reason).
    ///
    /// Timing fields are observed clock boundaries only (null = driver did not report):
    /// `queueMs` request→spawn, `ttftMs` spawn→first token, `durationMs` spawn→exit.
    public struct AnswerInfo: Codable, Equatable, Sendable {
        public var agentId: String
        public var modelId: String?
        public var status: Status
        /// Ms from run request accepted to this seat's CLI spawn. Null when unmeasured.
        public var queueMs: Int?
        /// Ms from spawn to first visible streamed delta. Null when unreported.
        public var ttftMs: Int?
        /// Ms of worker work-time (spawn → exit). Null when unmeasured.
        public var durationMs: Int?
        public var markdown: String?
        /// Absolute path when `markdown` is a run-relative design image file.
        public var outputAbsolutePath: String?
        public var error: ErrorEnvelope?
        public init(
            agentId: String, modelId: String? = nil, status: Status,
            queueMs: Int? = nil, ttftMs: Int? = nil, durationMs: Int? = nil,
            markdown: String? = nil, outputAbsolutePath: String? = nil, error: ErrorEnvelope? = nil
        ) {
            self.agentId = agentId; self.modelId = modelId; self.status = status
            self.queueMs = queueMs; self.ttftMs = ttftMs; self.durationMs = durationMs
            self.markdown = markdown
            self.outputAbsolutePath = outputAbsolutePath; self.error = error
        }
    }

    /// Structured design board projection for design-lane runs.
    public struct DesignBoard: Codable, Equatable, Sendable {
        public var targetShape: String
        public var screenshotPath: String?
        public var screenshotAbsolutePath: String?
        public var options: [DesignBoardOption]
        public var chosen: DesignBoardChosen?

        public init(
            targetShape: String,
            screenshotPath: String? = nil,
            screenshotAbsolutePath: String? = nil,
            options: [DesignBoardOption],
            chosen: DesignBoardChosen? = nil
        ) {
            self.targetShape = targetShape
            self.screenshotPath = screenshotPath
            self.screenshotAbsolutePath = screenshotAbsolutePath
            self.options = options
            self.chosen = chosen
        }
    }

    public struct DesignBoardOption: Codable, Equatable, Sendable {
        public var agentId: String
        public var modelId: String
        public var persona: String
        public var imagePath: String?
        public var absolutePath: String?
        public var status: Status
        public var failureReason: String?
        public var sessionId: String?

        public init(
            agentId: String, modelId: String, persona: String, imagePath: String? = nil,
            absolutePath: String? = nil, status: Status, failureReason: String? = nil,
            sessionId: String? = nil
        ) {
            self.agentId = agentId; self.modelId = modelId; self.persona = persona
            self.imagePath = imagePath; self.absolutePath = absolutePath; self.status = status
            self.failureReason = failureReason; self.sessionId = sessionId
        }
    }

    public struct DesignBoardChosen: Codable, Equatable, Sendable {
        public var agentId: String
        public var persona: String
        public var chosenAt: String?

        public init(agentId: String, persona: String, chosenAt: String? = nil) {
            self.agentId = agentId; self.persona = persona; self.chosenAt = chosenAt
        }
    }

    // MARK: - outcome

    /// Honest mechanical summary for fast gating — derived from worker terminal states
    /// and observed repo delta, never a judgment of work quality.
    public struct Outcome: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable {
            case completed, partial, failed, timedOut
        }
        public struct Proof: Codable, Equatable, Sendable {
            public var command: String
            public var exitCode: Int?
            public var passed: Bool
            public var outputTail: String

            public init(command: String, exitCode: Int?, passed: Bool, outputTail: String) {
                self.command = command
                self.exitCode = exitCode
                self.passed = passed
                self.outputTail = outputTail
            }
        }
        /// Driver-reported token counts (absent when the dialect emits none — never zero).
        public struct TokenUsage: Codable, Equatable, Sendable {
            public var inputTokens: Int?
            public var outputTokens: Int?

            public init(inputTokens: Int? = nil, outputTokens: Int? = nil) {
                self.inputTokens = inputTokens
                self.outputTokens = outputTokens
            }
        }
        /// Terminal observed wall clock. Null fields mean the observation was not recorded.
        public struct Timing: Codable, Equatable, Sendable {
            /// Ms from run `createdAt` to the latest worker `finishedAt`. Null when unmeasured.
            public var wallMs: Int?
            public init(wallMs: Int? = nil) { self.wallMs = wallMs }
        }
        public var status: Status
        public var committed: Bool
        public var headline: String
        /// Present when `--commit-message` was given — compares newest commit subject to the request.
        public var commitMessageMatched: Bool?
        /// Present when `--proof` was given — bounded subprocess result after worker settlement.
        public var proof: Proof?
        /// Present when the execution driver reported token usage on the wire.
        public var usage: TokenUsage?
        /// Observed wall timing for a terminal run.
        public var timing: Timing?

        public init(
            status: Status, committed: Bool, headline: String,
            commitMessageMatched: Bool? = nil, proof: Proof? = nil, usage: TokenUsage? = nil,
            timing: Timing? = nil
        ) {
            self.status = status
            self.committed = committed
            self.headline = headline
            self.commitMessageMatched = commitMessageMatched
            self.proof = proof
            self.usage = usage
            self.timing = timing
        }
    }

    // MARK: - stages / plan

    public struct StageInfo: Codable, Equatable, Sendable {
        public var id: String
        public var purpose: StagePurpose
        public var status: Status
        public var producedByAgentId: String?
        public var promptProfileId: String?
        public init(id: String, purpose: StagePurpose, status: Status, producedByAgentId: String? = nil, promptProfileId: String? = nil) {
            self.id = id; self.purpose = purpose; self.status = status
            self.producedByAgentId = producedByAgentId; self.promptProfileId = promptProfileId
        }
    }

    /// Synthesized-plan provenance. When the plan is the canonical result,
    /// markdown moves to `answer` and `plan.markdown` is null (Law 2).
    public struct Plan: Codable, Equatable, Sendable {
        public var status: Status
        public var writerAgentId: String?
        public var stageId: String?
        public var markdown: String?
        public init(status: Status, writerAgentId: String? = nil, stageId: String? = nil, markdown: String? = nil) {
            self.status = status; self.writerAgentId = writerAgentId
            self.stageId = stageId; self.markdown = markdown
        }
    }

    // MARK: - usage / warnings / errors / nextActions / audit

    /// Observed usage only. No forecasts of future cost, quota, or runtime.
    public struct Usage: Codable, Equatable, Sendable {
        public var cliCalls: Int
        public init(cliCalls: Int) { self.cliCalls = cliCalls }
    }

    public struct Warning: Codable, Equatable, Sendable {
        public var code: String?
        public var message: String
        public init(code: String? = nil, message: String) { self.code = code; self.message = message }
    }

    // `ErrorEnvelope` is the shared top-level type in `ErrorEnvelope.swift` —
    // reused by JSON `errors`, `answers[].error`, NDJSON `error.error`, and
    // `DoctorResult`. It is intentionally not nested here.

    /// A typed follow-up action plus the exact command to run it. `kind` is a
    /// closed set; the contract registry (CLI M1 step 2) becomes its owner and
    /// catalog. Add new kinds there, then regenerate — do not widen ad hoc.
    public struct NextAction: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            /// Open the polished HTML team artifact (primary finish for terminal runs).
            case showArtifact
            case showRun, export, showHistory
        }
        public var kind: Kind
        public var command: String
        public var label: String?
        public init(kind: Kind, command: String, label: String? = nil) {
            self.kind = kind; self.command = command; self.label = label
        }
    }

    public struct Audit: Codable, Equatable, Sendable {
        public var traceId: String
        public var runJournalPath: String
        public init(traceId: String, runJournalPath: String) {
            self.traceId = traceId; self.runJournalPath = runJournalPath
        }
    }
}
