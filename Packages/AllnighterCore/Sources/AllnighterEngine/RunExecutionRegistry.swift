import Foundation
import AllnighterCore

/// WL-PWR-S02 — in-process live mutating-run stop hook.
///
/// `alln kill` stamps the journal from any process; only the holder process can
/// release its flock. This registry lets that holder register a stop closure so
/// same-process kill frees the lane immediately (and cancels the worker/proof).
/// Cross-process kill still relies on worker PG stop + the holder noticing the
/// terminal journal on its next check / stream end.
actor RunExecutionRegistry {
    static let shared = RunExecutionRegistry()

    private var stops: [String: @Sendable () async -> Void] = [:]

    func register(runId: String, stop: @escaping @Sendable () async -> Void) {
        stops[runId] = stop
    }

    func unregister(runId: String) {
        stops[runId] = nil
    }

    /// Idempotent. No-op when this process does not own the run.
    func requestStop(runId: String) async {
        guard let stop = stops[runId] else { return }
        await stop()
    }
}

/// Per-run stop state owned by `RunService.runExecution`.
actor LiveRunStop {
    private let mutationAuthority: MutationAuthorityHold?
    private let writeLock: ExecutionLaneRegistry
    private var proofKey: String?
    private var proofToken: ExecutionLane.Token?
    private var warmKey: ExternalWorkerSession.Key?
    private var workerTask: Task<WorkerRunOutcome, Never>?
    private var proofTask: Task<RunProofResult, Never>?
    private(set) var stopRequested = false

    init(mutationAuthority: MutationAuthorityHold?, writeLock: ExecutionLaneRegistry) {
        self.mutationAuthority = mutationAuthority
        self.writeLock = writeLock
    }

    func setWarmKey(_ key: ExternalWorkerSession.Key?) {
        warmKey = key
    }

    func setWorkerTask(_ task: Task<WorkerRunOutcome, Never>) {
        workerTask = task
    }

    func setProof(key: String, token: ExecutionLane.Token) {
        proofKey = key
        proofToken = token
    }

    func setProofTask(_ task: Task<RunProofResult, Never>) {
        proofTask = task
    }

    func clearProofRegistration() {
        proofKey = nil
        proofToken = nil
        proofTask = nil
    }

    /// Stop worker/proof work and release this process's lane holds now.
    func performStop(warmPool: WarmWorkerPool) async {
        guard !stopRequested else { return }
        stopRequested = true
        workerTask?.cancel()
        proofTask?.cancel()
        await mutationAuthority?.releaseIfHeld(endReason: "killed")
        if let key = proofKey, let token = proofToken {
            await writeLock.release(key, token: token, endReason: "killed")
            proofKey = nil
            proofToken = nil
        }
        if let warmKey {
            await warmPool.shutdown(key: warmKey)
        }
    }
}
