import Foundation

/// `TeamRunJSON` — the first public machine contract for a team run
/// (docs/phases/CLI_Implementation_Contract.md §TeamRunJSON).
///
/// This is the shared shape that `alln --json`, the Mac/iOS presenters, and MCP
/// tool results all project from. It is intentionally **separate from the
/// internal persistence model** (`TeamRun`): the internal model may evolve, but
/// this public contract is versioned via `schemaVersion`/`contractVersion`.
///
/// Sub-types are nested so the public surface reads as one contract and does not
/// collide with the internal `Model`/`Worker`/`TeamRun`/`StageOutput` types.
public struct TeamRunJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var teamRun: RunInfo
    public var models: [ModelInfo]
    public var workers: [WorkerInfo]
    public var workerAnswers: [AnswerInfo]
    public var designBoard: DesignBoard?
    public var stages: [StageInfo]
    public var plan: Plan?
    public var usage: Usage
    public var warnings: [Warning]
    public var errors: [ErrorEnvelope]
    public var nextActions: [NextAction]
    public var audit: Audit

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        teamRun: RunInfo,
        models: [ModelInfo],
        workers: [WorkerInfo],
        workerAnswers: [AnswerInfo],
        designBoard: DesignBoard? = nil,
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
        self.models = models
        self.workers = workers
        self.workerAnswers = workerAnswers
        self.designBoard = designBoard
        self.stages = stages
        self.plan = plan
        self.usage = usage
        self.warnings = warnings
        self.errors = errors
        self.nextActions = nextActions
        self.audit = audit
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
        public var planWriterWorkerId: String?
        public var reproduceCommand: String?

        public init(
            id: String, status: Status, origin: Origin, originAgent: String? = nil,
            lane: String? = nil, type: String? = nil, effort: String? = nil,
            prompt: String, promptSource: PromptSource, createdAt: String,
            startedAt: String? = nil, completedAt: String? = nil, threadId: String? = nil,
            teamPresetId: String? = nil, teamDisplayName: String? = nil, outputKind: String? = nil,
            planWriterWorkerId: String? = nil, reproduceCommand: String? = nil
        ) {
            self.id = id; self.status = status; self.origin = origin
            self.originAgent = originAgent; self.lane = lane; self.type = type
            self.effort = effort; self.prompt = prompt; self.promptSource = promptSource
            self.createdAt = createdAt; self.startedAt = startedAt
            self.completedAt = completedAt; self.threadId = threadId
            self.teamPresetId = teamPresetId; self.teamDisplayName = teamDisplayName
            self.outputKind = outputKind; self.planWriterWorkerId = planWriterWorkerId
            self.reproduceCommand = reproduceCommand
        }
    }

    /// Prompt provenance — never the secret content of a `--file`.
    public struct PromptSource: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case positional, file, stdin }
        public var kind: Kind
        public var path: String?
        public init(kind: Kind, path: String? = nil) { self.kind = kind; self.path = path }
    }

    // MARK: - models / workers

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

    public struct WorkerInfo: Codable, Equatable, Sendable {
        public var id: String
        public var skillId: String?
        public var skillName: String?
        public var resolvedWorkerPromptSnapshot: String?
        public var modelId: String
        public var modelName: String
        public var sourceId: String
        public var purpose: WorkerPurpose
        public var instanceIndex: Int
        public init(id: String, skillId: String? = nil, skillName: String? = nil, resolvedWorkerPromptSnapshot: String? = nil, modelId: String, modelName: String, sourceId: String, purpose: WorkerPurpose, instanceIndex: Int) {
            self.id = id; self.skillId = skillId; self.skillName = skillName
            self.resolvedWorkerPromptSnapshot = resolvedWorkerPromptSnapshot
            self.modelId = modelId; self.modelName = modelName; self.sourceId = sourceId
            self.purpose = purpose; self.instanceIndex = instanceIndex
        }
    }

    /// One answer or failure per answer worker. A failed worker is shown failed,
    /// never hidden (`error` carries the reason).
    public struct AnswerInfo: Codable, Equatable, Sendable {
        public var workerId: String
        public var modelId: String?
        public var status: Status
        public var durationMs: Int?
        public var markdown: String?
        /// Absolute path when `markdown` is a run-relative design image file.
        public var outputAbsolutePath: String?
        public var error: ErrorEnvelope?
        public init(
            workerId: String, modelId: String? = nil, status: Status, durationMs: Int? = nil,
            markdown: String? = nil, outputAbsolutePath: String? = nil, error: ErrorEnvelope? = nil
        ) {
            self.workerId = workerId; self.modelId = modelId; self.status = status
            self.durationMs = durationMs; self.markdown = markdown
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
        public var workerId: String
        public var modelId: String
        public var persona: String
        public var imagePath: String?
        public var absolutePath: String?
        public var status: Status
        public var failureReason: String?
        public var sessionId: String?

        public init(
            workerId: String, modelId: String, persona: String, imagePath: String? = nil,
            absolutePath: String? = nil, status: Status, failureReason: String? = nil,
            sessionId: String? = nil
        ) {
            self.workerId = workerId; self.modelId = modelId; self.persona = persona
            self.imagePath = imagePath; self.absolutePath = absolutePath; self.status = status
            self.failureReason = failureReason; self.sessionId = sessionId
        }
    }

    public struct DesignBoardChosen: Codable, Equatable, Sendable {
        public var workerId: String
        public var persona: String
        public var chosenAt: String?

        public init(workerId: String, persona: String, chosenAt: String? = nil) {
            self.workerId = workerId; self.persona = persona; self.chosenAt = chosenAt
        }
    }

    // MARK: - stages / plan

    public struct StageInfo: Codable, Equatable, Sendable {
        public var id: String
        public var purpose: StagePurpose
        public var status: Status
        public var producedByWorkerId: String?
        public var promptProfileId: String?
        public init(id: String, purpose: StagePurpose, status: Status, producedByWorkerId: String? = nil, promptProfileId: String? = nil) {
            self.id = id; self.purpose = purpose; self.status = status
            self.producedByWorkerId = producedByWorkerId; self.promptProfileId = promptProfileId
        }
    }

    /// The final synthesized result. When `status == .done`, `writerWorkerId` must
    /// be non-null and equal to `teamRun.planWriterWorkerId`.
    public struct Plan: Codable, Equatable, Sendable {
        public var status: Status
        public var writerWorkerId: String?
        public var stageId: String?
        public var markdown: String
        public init(status: Status, writerWorkerId: String? = nil, stageId: String? = nil, markdown: String) {
            self.status = status; self.writerWorkerId = writerWorkerId
            self.stageId = stageId; self.markdown = markdown
        }
    }

    // MARK: - usage / warnings / errors / nextActions / audit

    /// Observed usage only. No estimates of future cost, quota, or runtime.
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
    // reused by JSON `errors`, `workerAnswers[].error`, NDJSON `error.error`, and
    // `DoctorResult`. It is intentionally not nested here.

    /// A typed follow-up action plus the exact command to run it. `kind` is a
    /// closed set; the contract registry (CLI M1 step 2) becomes its owner and
    /// catalog. Add new kinds there, then regenerate — do not widen ad hoc.
    public struct NextAction: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
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
