import Foundation

/// `alln pair slice` / `alln pair run` wire shapes (Pair_Programming_Team §10).
public struct PairSliceJSON: Codable, Equatable, Sendable {
    public struct Gate: Codable, Equatable, Sendable {
        public var decision: String
        public var code: String?
        public var reason: String?

        public init(decision: String, code: String? = nil, reason: String? = nil) {
            self.decision = decision
            self.code = code
            self.reason = reason
        }
    }

    public struct Check: Codable, Equatable, Sendable {
        public var exitCode: Int?
        public var stdoutTail: String?
        public var timedOut: Bool

        public init(exitCode: Int? = nil, stdoutTail: String? = nil, timedOut: Bool = false) {
            self.exitCode = exitCode
            self.stdoutTail = stdoutTail
            self.timedOut = timedOut
        }
    }

    public var contractVersion: String
    public var sliceId: String
    public var status: String
    public var gate: Gate
    public var check: Check?
    public var parentRunId: String?
    public var childRunId: String?
    public var plannerWorkerId: String?
    public var executorWorkerId: String?

    public init(
        contractVersion: String,
        sliceId: String,
        status: String,
        gate: Gate,
        check: Check? = nil,
        parentRunId: String? = nil,
        childRunId: String? = nil,
        plannerWorkerId: String? = nil,
        executorWorkerId: String? = nil
    ) {
        self.contractVersion = contractVersion
        self.sliceId = sliceId
        self.status = status
        self.gate = gate
        self.check = check
        self.parentRunId = parentRunId
        self.childRunId = childRunId
        self.plannerWorkerId = plannerWorkerId
        self.executorWorkerId = executorWorkerId
    }
}

public struct PairQueueJSON: Codable, Equatable, Sendable {
    public struct SliceResult: Codable, Equatable, Sendable {
        public var sliceId: String
        public var status: String
        public var checkExitCode: Int?
        public var childRunId: String?
        public var escalatedReason: String?
        public var resolvedBy: String?
        public var plannerRunId: String?
        public var executorAttempts: Int?

        public init(
            sliceId: String,
            status: String,
            checkExitCode: Int? = nil,
            childRunId: String? = nil,
            escalatedReason: String? = nil,
            resolvedBy: String? = nil,
            plannerRunId: String? = nil,
            executorAttempts: Int? = nil
        ) {
            self.sliceId = sliceId
            self.status = status
            self.checkExitCode = checkExitCode
            self.childRunId = childRunId
            self.escalatedReason = escalatedReason
            self.resolvedBy = resolvedBy
            self.plannerRunId = plannerRunId
            self.executorAttempts = executorAttempts
        }
    }

    public var contractVersion: String
    public var passed: Int
    public var plannerResolved: Int
    public var escalated: Int
    public var stoppedReason: String?
    public var slices: [SliceResult]

    public init(
        contractVersion: String,
        passed: Int,
        plannerResolved: Int = 0,
        escalated: Int,
        stoppedReason: String? = nil,
        slices: [SliceResult]
    ) {
        self.contractVersion = contractVersion
        self.passed = passed
        self.plannerResolved = plannerResolved
        self.escalated = escalated
        self.stoppedReason = stoppedReason
        self.slices = slices
    }
}

public extension PairSliceJSON.Gate {
    static func from(_ decision: SliceGate.Decision) -> PairSliceJSON.Gate {
        switch decision {
        case .allowed:
            return .init(decision: "allowed")
        case .blocked(let code, let reason):
            return .init(decision: "blocked", code: code, reason: reason)
        }
    }
}

/// NDJSON progress events emitted during `pair run` (before the final summary).
public struct PairQueueProgressJSON: Codable, Equatable, Sendable {
    public var contractVersion: String
    public var event: String
    public var sliceId: String
    public var status: String?
    public var elapsedSeconds: Int?

    public init(
        contractVersion: String,
        event: String,
        sliceId: String,
        status: String? = nil,
        elapsedSeconds: Int? = nil
    ) {
        self.contractVersion = contractVersion
        self.event = event
        self.sliceId = sliceId
        self.status = status
        self.elapsedSeconds = elapsedSeconds
    }
}

/// `alln pair status` / MCP `pair_status` wire shape.
public struct PairStatusJSON: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var sliceId: String
        public var status: String
        public var childRunId: String?
        public var elapsedSeconds: Int?
        public var guidance: String

        public init(
            sliceId: String,
            status: String,
            childRunId: String? = nil,
            elapsedSeconds: Int? = nil,
            guidance: String
        ) {
            self.sliceId = sliceId
            self.status = status
            self.childRunId = childRunId
            self.elapsedSeconds = elapsedSeconds
            self.guidance = guidance
        }
    }

    public var contractVersion: String
    public var queuePath: String
    public var entries: [Entry]

    public init(contractVersion: String, queuePath: String, entries: [Entry]) {
        self.contractVersion = contractVersion
        self.queuePath = queuePath
        self.entries = entries
    }
}

/// Progress events surfaced by `PairCoordinator.runQueue`.
public enum PairQueueProgressEvent: Sendable, Equatable {
    case sliceRunning(sliceId: String)
    case sliceFinished(sliceId: String, status: String, elapsedSeconds: Int)
}

public typealias PairQueueProgressHandler = @Sendable (PairQueueProgressEvent) -> Void
