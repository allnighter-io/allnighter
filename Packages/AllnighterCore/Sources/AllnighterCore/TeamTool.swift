import Foundation

/// The normalized input to the team tool (RB6), shared across CLI / MCP / HTTP.
public struct TeamRequest: Codable, Sendable, Equatable {
    public var question: String
    public var presetId: String?
    /// Optional bounded snippet the calling agent wants considered.
    public var context: String?
    /// `team_ask` client timeout (seconds). When set, the tool may return a
    /// `runId` to poll if the run is still in flight — never branches on a
    /// predicted duration.
    public var waitSeconds: Int?

    public init(question: String, presetId: String? = nil, context: String? = nil, waitSeconds: Int? = nil) {
        self.question = question
        self.presetId = presetId
        self.context = context
        self.waitSeconds = waitSeconds
    }
}

/// The structured result returned to a calling agent (RB6). `finalSpec` stays nil
/// until RB3 presets are exposed; `invocations` is observed after the run.
public struct TeamToolResult: Codable, Sendable, Equatable {
    public var runId: String
    public var origin: RunOrigin
    public var preset: String
    public var status: RunStatus
    public var createdAt: Date
    public var plan: String?
    public var finalSpec: String?
    public var analysis: PlanAnalysis?
    public var partials: [WorkerFailure]
    public var contextTruncated: Bool
    public var invocations: Int
    public var note: String

    public init(
        runId: String, origin: RunOrigin, preset: String, status: RunStatus, createdAt: Date,
        plan: String? = nil, finalSpec: String? = nil, analysis: PlanAnalysis? = nil,
        partials: [WorkerFailure] = [], contextTruncated: Bool = false, invocations: Int = 0, note: String = ""
    ) {
        self.runId = runId
        self.origin = origin
        self.preset = preset
        self.status = status
        self.createdAt = createdAt
        self.plan = plan
        self.finalSpec = finalSpec
        self.analysis = analysis
        self.partials = partials
        self.contextTruncated = contextTruncated
        self.invocations = invocations
        self.note = note
    }

    /// A compact, honest error result (recursion refused, busy, no preset, …).
    public static func refused(reason: String, preset: String = "", now: Date) -> TeamToolResult {
        TeamToolResult(runId: "", origin: .gui, preset: preset, status: .failed, createdAt: now, note: reason)
    }
}

/// One past judgment surfaced by `team_recall` (read-only, zero cost).
public struct RecallResult: Codable, Sendable, Equatable, Identifiable {
    public var runId: String
    public var prompt: String
    public var createdAt: Date
    public var planExcerpt: String
    public var id: String { runId }
    public init(runId: String, prompt: String, createdAt: Date, planExcerpt: String) {
        self.runId = runId
        self.prompt = prompt
        self.createdAt = createdAt
        self.planExcerpt = planExcerpt
    }
}

/// Tool configuration (`Config/Tool/config.json`).
public struct ToolConfig: Codable, Sendable, Equatable {
    public struct Transports: Codable, Sendable, Equatable {
        public var cli: Bool, mcp: Bool, http: Bool
        public init(cli: Bool = true, mcp: Bool = true, http: Bool = false) { self.cli = cli; self.mcp = mcp; self.http = http }
    }
    public var enabledTransports: Transports
    public var exposedPresetIds: [String]
    public var defaultPresetId: String
    public var maxConcurrentTeamRuns: Int
    public var maxTeamRunDepth: Int
    public var httpPort: Int
    public var contextByteLimit: Int
    public var allowSinglePassthroughAtDepth: Bool

    public init(
        enabledTransports: Transports = Transports(),
        exposedPresetIds: [String] = ["preset_fast", "preset_quality", "preset_budget", "preset_self_double", "preset_six_default"],
        defaultPresetId: String = "preset_fast",
        maxConcurrentTeamRuns: Int = 2,
        maxTeamRunDepth: Int = 1,
        httpPort: Int = 8787,
        contextByteLimit: Int = 8000,
        allowSinglePassthroughAtDepth: Bool = false
    ) {
        self.enabledTransports = enabledTransports
        self.exposedPresetIds = exposedPresetIds
        self.defaultPresetId = defaultPresetId
        self.maxConcurrentTeamRuns = maxConcurrentTeamRuns
        self.maxTeamRunDepth = maxTeamRunDepth
        self.httpPort = httpPort
        self.contextByteLimit = contextByteLimit
        self.allowSinglePassthroughAtDepth = allowSinglePassthroughAtDepth
    }
}
