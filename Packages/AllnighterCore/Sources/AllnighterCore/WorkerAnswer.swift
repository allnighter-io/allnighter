import Foundation

/// The exact prompt sent to one worker.
public struct WorkerPrompt: Codable, Sendable, Equatable {
    public var workerId: String
    public var modelId: String
    public var text: String

    public init(workerId: String, modelId: String, text: String) {
        self.workerId = workerId
        self.modelId = modelId
        self.text = text
    }
}

/// One worker's output from a team run.
public struct WorkerAnswer: Codable, Sendable, Equatable, Identifiable {
    public var workerId: String
    public var modelId: String
    public var status: WorkerAnswerStatus
    public var output: String?
    public var errorKind: WorkerAnswerErrorKind?
    public var errorReason: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var durationMs: Int?
    /// Queue wait: ms from the run REQUEST being accepted to the worker CLI actually spawning
    /// (`startedAt`). Captures write-lock/lane wait + team resolution + context/attachment
    /// staging — the "nothing's happening yet" gap before the CLI even starts. nil if unmeasured.
    public var queueMs: Int?
    /// Time-to-first-token: ms from CLI spawn to the first visible streamed delta. The dead air
    /// before any text renders. nil on the non-streaming path. (See `RunTiming.ttftMs`.)
    public var ttftMs: Int?
    /// Spawn-gate wait: ms this seat spent blocked in the per-driver `DriverConcurrencyGate`
    /// (`maxConcurrentSpawns` serialization) before its CLI spawned. nil when the driver is
    /// ungated. A sub-portion of `queueMs`: `queueMs − gateWaitMs` ≈ lane/lock/resolution/staging.
    /// Lets a run artifact tell "seat N queued behind earlier long runners" apart from a CLI stall.
    public var gateWaitMs: Int?
    public var exitCode: Int?
    /// Sourced capacity/cooldown fact from the worker CLI attempt (nonzero exit only).
    public var capacityObservation: CapacityObservation?
    /// Worker_Session_Continuity receipt: the vendor CLI session id this turn used/established
    /// (`--resume`d or minted/captured). Lets a run artifact PROVE turn 2 resumed turn 1.
    public var vendorSessionId: String?
    /// Spawn facts for triage: cwd, timeout kind, byte counts, stderr tail.
    public var spawnDiagnostics: WorkerSpawnDiagnostics?

    public var id: String { workerId }

    public init(
        workerId: String,
        modelId: String,
        status: WorkerAnswerStatus = .queued,
        output: String? = nil,
        errorKind: WorkerAnswerErrorKind? = nil,
        errorReason: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        durationMs: Int? = nil,
        queueMs: Int? = nil,
        ttftMs: Int? = nil,
        gateWaitMs: Int? = nil,
        exitCode: Int? = nil,
        capacityObservation: CapacityObservation? = nil,
        vendorSessionId: String? = nil,
        spawnDiagnostics: WorkerSpawnDiagnostics? = nil
    ) {
        self.workerId = workerId
        self.modelId = modelId
        self.status = status
        self.output = output
        self.errorKind = errorKind
        self.errorReason = errorReason
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationMs = durationMs
        self.queueMs = queueMs
        self.ttftMs = ttftMs
        self.gateWaitMs = gateWaitMs
        self.exitCode = exitCode
        self.capacityObservation = capacityObservation
        self.vendorSessionId = vendorSessionId
        self.spawnDiagnostics = spawnDiagnostics
    }

    public var hasAnswer: Bool {
        status == .done && (output?.isEmpty == false)
    }
}
