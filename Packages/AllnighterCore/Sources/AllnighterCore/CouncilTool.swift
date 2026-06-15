import Foundation

/// The normalized input to the council tool (RB6), shared across CLI / MCP / HTTP.
public struct CouncilRequest: Codable, Sendable, Equatable {
    public var question: String
    public var presetId: String?
    /// Optional bounded snippet the calling agent wants considered.
    public var context: String?
    /// `council_ask` client timeout (seconds). When set, the tool may return a
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
public struct CouncilToolResult: Codable, Sendable, Equatable {
    public var runId: String
    public var origin: RunOrigin
    public var preset: String
    public var status: RunStatus
    public var createdAt: Date
    public var masterPlan: String?
    public var finalSpec: String?
    public var analysis: JudgeAnalysis?
    public var partials: [SeatFailure]
    public var contextTruncated: Bool
    public var invocations: Int
    public var note: String

    public init(
        runId: String, origin: RunOrigin, preset: String, status: RunStatus, createdAt: Date,
        masterPlan: String? = nil, finalSpec: String? = nil, analysis: JudgeAnalysis? = nil,
        partials: [SeatFailure] = [], contextTruncated: Bool = false, invocations: Int = 0, note: String = ""
    ) {
        self.runId = runId
        self.origin = origin
        self.preset = preset
        self.status = status
        self.createdAt = createdAt
        self.masterPlan = masterPlan
        self.finalSpec = finalSpec
        self.analysis = analysis
        self.partials = partials
        self.contextTruncated = contextTruncated
        self.invocations = invocations
        self.note = note
    }

    /// A compact, honest error result (recursion refused, busy, no preset, …).
    public static func refused(reason: String, preset: String = "", now: Date) -> CouncilToolResult {
        CouncilToolResult(runId: "", origin: .gui, preset: preset, status: .failed, createdAt: now, note: reason)
    }
}

/// One past judgment surfaced by `council_recall` (read-only, zero cost).
public struct RecallResult: Codable, Sendable, Equatable, Identifiable {
    public var runId: String
    public var prompt: String
    public var createdAt: Date
    public var masterPlanExcerpt: String
    public var id: String { runId }
    public init(runId: String, prompt: String, createdAt: Date, masterPlanExcerpt: String) {
        self.runId = runId
        self.prompt = prompt
        self.createdAt = createdAt
        self.masterPlanExcerpt = masterPlanExcerpt
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
    public var maxConcurrentCouncils: Int
    public var maxCouncilDepth: Int
    public var httpPort: Int
    public var contextByteLimit: Int
    public var allowSinglePassthroughAtDepth: Bool

    public init(
        enabledTransports: Transports = Transports(),
        exposedPresetIds: [String] = ["preset_fast", "preset_quality", "preset_budget", "preset_self_double", "preset_six_default"],
        defaultPresetId: String = "preset_fast",
        maxConcurrentCouncils: Int = 2,
        maxCouncilDepth: Int = 1,
        httpPort: Int = 8787,
        contextByteLimit: Int = 8000,
        allowSinglePassthroughAtDepth: Bool = false
    ) {
        self.enabledTransports = enabledTransports
        self.exposedPresetIds = exposedPresetIds
        self.defaultPresetId = defaultPresetId
        self.maxConcurrentCouncils = maxConcurrentCouncils
        self.maxCouncilDepth = maxCouncilDepth
        self.httpPort = httpPort
        self.contextByteLimit = contextByteLimit
        self.allowSinglePassthroughAtDepth = allowSinglePassthroughAtDepth
    }
}
