import Foundation
import AllnighterCore

/// Wraps a `WorkerInvoking` to add per-driver spawn-gate serialization — the ONE
/// behavior AgentOS's `DefaultWorkerRunner` does not itself do. Fragile CLIs (agy,
/// cursor) declare `maxConcurrentSpawns` on their manifest (`01` §4.3); this decorator
/// acquires that lane's permit from `DriverConcurrencyGate` BEFORE handing the
/// invocation to `inner`, measures the wait, and patches it onto the terminal event's
/// `result.timing.gateWaitMs` — mirroring the acquire-before-spawn /
/// release-on-settle semantics `WorkerRunner.invoke`/`invokeStreaming` use today (see
/// `WorkerRunner.swift`'s `acquireDriverSpawnGate`/`releaseDriverSpawnGate`, NOT
/// modified here). `DriverConcurrencyGate` itself is untouched — this only drives it
/// from the new `WorkerInvoking` seam. A manifest with no `maxConcurrentSpawns` is
/// ungated and passes straight through, with no actor hop.
public struct GatedWorkerRunner: WorkerInvoking {
    private let inner: any WorkerInvoking
    private let gate: DriverConcurrencyGate
    private let now: @Sendable () -> Date

    public init(
        inner: any WorkerInvoking,
        gate: DriverConcurrencyGate = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.inner = inner
        self.gate = gate
        self.now = now
    }

    public func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        guard let limit = invocation.manifest.maxConcurrentSpawns else {
            return inner.invoke(invocation)
        }
        let driverId = invocation.manifest.id
        let gate = self.gate
        let inner = self.inner
        let now = self.now

        return AsyncThrowingStream { continuation in
            let task = Task {
                let state = GateHoldState()
                let requestedAt = now()
                do {
                    try await gate.acquire(driverId: driverId, limit: limit)
                } catch {
                    let (kind, reason) = Self.gateFailure(error, driverId: driverId)
                    continuation.yield(.failed(WorkerRunResult(status: .failed, errorKind: kind, errorReason: reason)))
                    continuation.finish()
                    return
                }
                await state.markHeld()
                let gateWaitMs = max(0, Int(now().timeIntervalSince(requestedAt) * 1000))

                func releaseIfHeld() async {
                    if await state.markReleased() {
                        await gate.release(driverId: driverId)
                    }
                }

                do {
                    for try await event in inner.invoke(invocation) {
                        switch event {
                        case .completed(var result):
                            result.timing.gateWaitMs = gateWaitMs
                            continuation.yield(.completed(result))
                        case .failed(var result):
                            result.timing.gateWaitMs = gateWaitMs
                            continuation.yield(.failed(result))
                        default:
                            continuation.yield(event)
                        }
                    }
                    await releaseIfHeld()
                    continuation.finish()
                } catch {
                    await releaseIfHeld()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func gateFailure(_ error: Error, driverId: String) -> (WorkerAnswerErrorKind, String) {
        if error is CancellationError {
            return (.cancelled, "spawn gate cancelled")
        }
        if case DriverConcurrencyGateError.acquireTimedOut(let d) = error {
            return (.timedOut, "spawn gate timed out for \(d)")
        }
        return (.timedOut, "spawn gate: \(error)")
    }
}

/// Tracks whether this run currently holds a gate permit, so cancellation (which
/// races the acquire/run/release sequence) never double-releases or releases a
/// permit this run never actually held.
private actor GateHoldState {
    private var held = false
    private var released = false

    func markHeld() { held = true }

    /// Returns true exactly once, the first time a held-and-not-yet-released permit
    /// is released.
    func markReleased() -> Bool {
        guard held, !released else { return false }
        released = true
        return true
    }
}
