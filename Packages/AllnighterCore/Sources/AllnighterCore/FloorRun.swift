import Foundation

// MARK: - Team Run Floor (docs/phases/Team_Run_Floor.md)

/// The **Floor**: the inspectable workroom and receipt for one team run, projected
/// over a persisted `TeamRun`. A projection — never a second run store. `floor.json`
/// is derived and regenerable from `run.json` plus artifact metadata.
public struct FloorRun: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var run: Run
    public var intent: Intent
    public var team: Team
    public var workerLanes: [FloorWorkerLane]
    public var floorReturn: FloorReturn?
    public var nextActions: [FloorNextAction]
    /// Every durable run artifact, flattened (F-S01). Refs are run-relative, never
    /// absolute paths; the app resolves them to local files.
    public var artifacts: [RunArtifactRef]
    /// The "team worked in parallel" event list (F-S04), derived from sourced
    /// timestamps only — missing timestamps are absent, never invented.
    public var timeline: [FloorTimelineEvent]
    public var warnings: [String]
    public var errors: [ErrorEnvelope]
    public var audit: Audit

    public init(schemaVersion: Int = 1, run: Run, intent: Intent, team: Team,
                workerLanes: [FloorWorkerLane] = [], floorReturn: FloorReturn? = nil,
                nextActions: [FloorNextAction] = [], artifacts: [RunArtifactRef] = [],
                timeline: [FloorTimelineEvent] = [],
                warnings: [String] = [], errors: [ErrorEnvelope] = [], audit: Audit = .init()) {
        self.schemaVersion = schemaVersion
        self.run = run; self.intent = intent; self.team = team
        self.workerLanes = workerLanes; self.floorReturn = floorReturn
        self.nextActions = nextActions; self.artifacts = artifacts; self.timeline = timeline
        self.warnings = warnings; self.errors = errors; self.audit = audit
    }

    /// Lifecycle of a Floor run, normalized from `RunStatus`.
    public enum Status: String, Codable, Sendable, CaseIterable {
        case queued, running, done, failed, timedOut, cancelled, interrupted
    }

    public struct Run: Codable, Sendable, Equatable {
        public var id: String
        public var projectId: String?
        public var threadId: String?
        public var status: Status
        /// The public family / craft (`signal|code|design|copy`). `nil` for legacy
        /// runs with no recorded lane.
        public var family: String?
        public var mutating: Bool
        public var origin: String
        public var originAgent: String?
        public var createdAt: Date
        public var reproduceCommand: String?

        public init(id: String, projectId: String? = nil, threadId: String? = nil,
                    status: Status, family: String? = nil,
                    mutating: Bool = false, origin: String, originAgent: String? = nil,
                    createdAt: Date, reproduceCommand: String? = nil) {
            self.id = id; self.projectId = projectId; self.threadId = threadId
            self.status = status; self.family = family
            self.mutating = mutating; self.origin = origin; self.originAgent = originAgent
            self.createdAt = createdAt; self.reproduceCommand = reproduceCommand
        }
    }

    /// What the user sent to the team — not what the team later inferred.
    public struct Intent: Codable, Sendable, Equatable {
        public var prompt: String
        public var threadId: String?
        public init(prompt: String, threadId: String? = nil) {
            self.prompt = prompt; self.threadId = threadId
        }
    }

    public struct Team: Codable, Sendable, Equatable {
        public var teamId: String?
        public var displayName: String?
        public var family: String?
        public var outputKind: String?
        public var workerCount: Int
        public var modelCount: Int
        public var leadAgentId: String?
        public init(teamId: String? = nil, displayName: String? = nil, family: String? = nil,
                    outputKind: String? = nil, workerCount: Int = 0, modelCount: Int = 0,
                    leadAgentId: String? = nil) {
            self.teamId = teamId; self.displayName = displayName; self.family = family
            self.outputKind = outputKind; self.workerCount = workerCount
            self.modelCount = modelCount; self.leadAgentId = leadAgentId
        }
    }

    public struct Audit: Codable, Sendable, Equatable {
        public var runJournalPath: String?
        public var traceId: String?
        public init(runJournalPath: String? = nil, traceId: String? = nil) {
            self.runJournalPath = runJournalPath; self.traceId = traceId
        }
    }
}

/// One worker's inspectable lane. Every worker answer produces a lane — including
/// failed, timed-out, skipped, and cancelled workers (a failure is shown, never
/// hidden). `summary` is a scan excerpt; the raw answer is the durable artifact
/// (added in F-S01).
public struct FloorWorkerLane: Codable, Sendable, Equatable, Identifiable {
    public enum Purpose: String, Codable, Sendable { case answer, review, lead, stage }
    public var agentId: String
    public var skillId: String?
    public var skillName: String?
    public var modelId: String
    public var purpose: Purpose
    public var status: String
    public var startedAt: Date?
    public var finishedAt: Date?
    public var durationMs: Int?
    public var exitCode: Int?
    public var summary: String?
    /// The worker's durable answer/metadata artifacts (F-S01). The raw answer is
    /// the artifact; `summary` is only a scan excerpt.
    public var artifactRefs: [RunArtifactRef]
    /// The resolved worker prompt snapshot — local-only, hidden by default, but
    /// available for audit/debug.
    public var promptArtifactRef: RunArtifactRef?
    public var error: String?

    public var id: String { agentId }

    public init(agentId: String, skillId: String? = nil, skillName: String? = nil,
                modelId: String, purpose: Purpose, status: String,
                startedAt: Date? = nil, finishedAt: Date? = nil, durationMs: Int? = nil,
                exitCode: Int? = nil, summary: String? = nil,
                artifactRefs: [RunArtifactRef] = [], promptArtifactRef: RunArtifactRef? = nil,
                error: String? = nil) {
        self.agentId = agentId; self.skillId = skillId; self.skillName = skillName
        self.modelId = modelId; self.purpose = purpose; self.status = status
        self.startedAt = startedAt; self.finishedAt = finishedAt; self.durationMs = durationMs
        self.exitCode = exitCode; self.summary = summary
        self.artifactRefs = artifactRefs; self.promptArtifactRef = promptArtifactRef
        self.error = error
    }
}

/// A stable, run-relative pointer to one durable run artifact (F-S01). Public JSON
/// uses `relativePath` (never absolute); the app resolves it under the run dir.
public struct RunArtifactRef: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case workerAnswer, workerPrompt, workerMetadata, stageOutput, receipt
        case returnMarkdown, insightJSON, bundle, source
    }
    public var id: String
    public var runId: String
    public var kind: Kind
    public var title: String
    public var relativePath: String
    public var mimeType: String
    public var agentId: String?
    public var stageId: String?
    public var createdAt: Date
    public var contentSHA256: String?
    public var localOnly: Bool

    public init(id: String, runId: String, kind: Kind, title: String, relativePath: String,
                mimeType: String, agentId: String? = nil, stageId: String? = nil,
                createdAt: Date, contentSHA256: String? = nil, localOnly: Bool = false) {
        self.id = id; self.runId = runId; self.kind = kind; self.title = title
        self.relativePath = relativePath; self.mimeType = mimeType
        self.agentId = agentId; self.stageId = stageId; self.createdAt = createdAt
        self.contentSHA256 = contentSHA256; self.localOnly = localOnly
    }

    /// A filesystem-safe stem for a worker id (e.g. `model_grok#0` → `model_grok_0`).
    /// Shared by the artifact writer (RunStore) and the projector so paths match.
    public static func safeStem(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
    }
}

/// The typed return on the Floor's right side. Not always a generic plan — F-S02/
/// S03 enrich this (Signal becomes `kind: insight`).
public struct FloorReturn: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case insight, plan, board, draft, proposal, proofPacket, audit
    }
    public var kind: Kind
    public var status: String
    public var title: String
    public var summaryMarkdown: String?
    public var producedByAgentId: String?
    public var stageId: String?
    public var artifactRefs: [RunArtifactRef]
    /// The typed Signal output, present on `kind == .insight` runs when the Insight
    /// Writer emitted a parseable structured block (F-S03).
    public var insight: SignalInsight?

    public init(kind: Kind, status: String, title: String,
                summaryMarkdown: String? = nil, producedByAgentId: String? = nil,
                stageId: String? = nil, artifactRefs: [RunArtifactRef] = [],
                insight: SignalInsight? = nil) {
        self.kind = kind; self.status = status; self.title = title
        self.summaryMarkdown = summaryMarkdown; self.producedByAgentId = producedByAgentId
        self.stageId = stageId; self.artifactRefs = artifactRefs; self.insight = insight
    }
}

/// One event in the Floor's converge timeline (F-S04). Derived from run/worker/
/// stage timestamps; an event is emitted only when its timestamp is sourced.
public struct FloorTimelineEvent: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case runQueued, runStarted, workerStarted, workerReturned, workerFailed
        case stageStarted, stageFinished, synthesisStarted, synthesisFinished, runFinished
    }
    public var id: String
    public var runId: String
    public var kind: Kind
    public var at: Date
    public var agentId: String?
    public var stageId: String?
    public var status: String?

    public init(id: String, runId: String, kind: Kind, at: Date,
                agentId: String? = nil, stageId: String? = nil, status: String? = nil) {
        self.id = id; self.runId = runId; self.kind = kind; self.at = at
        self.agentId = agentId; self.stageId = stageId; self.status = status
    }
}

/// A typed Floor next action. Mutating work is represented by the run itself and
/// guarded by the repo write lock.
public struct FloorNextAction: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case openArtifact, copyReturn, exportFloor, sendTeam, draftCopy, createCodeProposal
        case createDesignBrief, savePending, ignore
        case monitorExternally, showRun, showHistory
        /// The two composer-opening next moves on the GUI Floor card: hand the synthesis to
        /// a new Send-to-Team run, or continue the current Auto/default conversation.
        case askAnotherTeam, continueWithAuto
    }
    public var id: String
    public var kind: Kind
    public var label: String
    public var mutating: Bool
    public var command: String?
    public var disabledReason: String?

    public init(id: String, kind: Kind, label: String, mutating: Bool = false,
                command: String? = nil, disabledReason: String? = nil) {
        self.id = id; self.kind = kind; self.label = label
        self.mutating = mutating
        self.command = command; self.disabledReason = disabledReason
    }
}
