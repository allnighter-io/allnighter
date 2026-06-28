import Foundation

public enum DriverConcurrencyGateError: Error, Sendable, Equatable {
    case acquireTimedOut(driverId: String)
}

/// Process-wide, per-driver spawn limiter. Some headless CLIs cannot survive
/// concurrent invocation — they deadlock or corrupt a shared on-disk resource
/// (a singleton session dir, a per-invocation config rewritten via temp-rename).
/// Team fan-out (`CatalogRunCoordinator`) spawns every seat in parallel via a
/// `withTaskGroup`, so two seats on the same fragile driver collide.
///
/// This gate is the FIFO "one-running-per-lane" pattern applied at the right
/// altitude: the WORKER-SPAWN chokepoint, keyed by driver id. A driver declares
/// its ceiling as data (`DriverManifest.maxConcurrentSpawns`); absent ⇒ unlimited
/// (no gating, no actor hop). Seats that exceed a driver's ceiling queue and run
/// serially; every other driver stays fully parallel. The limit is global to the
/// process, so it also covers two concurrent team runs or a team seat overlapping
/// a single-lane chat on the same driver.
///
/// Proven values (see `scripts/cli-concurrency-spike.py`): antigravity=1 (agy
/// deadlocks on its singleton brain dir), cursor_agent=1 (races on
/// ~/.cursor/cli-config.json). claude/codex/grok are parallel-safe ⇒ no limit.
public actor DriverConcurrencyGate {
    public static let shared = DriverConcurrencyGate()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct Lane {
        let limit: Int
        var active = 0
        var waiters: [Waiter] = []
    }
    private var lanes: [String: Lane] = [:]

    public init() {}

    /// Acquire one permit for `driverId`. Returns immediately when a slot is free,
    /// otherwise suspends FIFO until a holder releases. `limit` is clamped to ≥1; the
    /// first acquire for a driver fixes its lane limit.
    public func acquire(
        driverId: String,
        limit: Int,
        timeout: Duration = .seconds(300)
    ) async throws {
        let cap = max(1, limit)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.acquireSlot(driverId: driverId, cap: cap)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw DriverConcurrencyGateError.acquireTimedOut(driverId: driverId)
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func acquireSlot(driverId: String, cap: Int) async throws {
        var lane = lanes[driverId] ?? Lane(limit: cap)
        if lane.active < lane.limit {
            lane.active += 1
            lanes[driverId] = lane
            return
        }
        lanes[driverId] = lane
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                guard var lane = lanes[driverId] else {
                    cont.resume(throwing: DriverConcurrencyGateError.acquireTimedOut(driverId: driverId))
                    return
                }
                lane.waiters.append(Waiter(id: waiterID, continuation: cont))
                lanes[driverId] = lane
            }
        } onCancel: {
            Task { await self.cancelWaiter(driverId: driverId, id: waiterID) }
        }
    }

    private func cancelWaiter(driverId: String, id: UUID) {
        guard var lane = lanes[driverId],
              let index = lane.waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = lane.waiters.remove(at: index)
        lanes[driverId] = lane
        waiter.continuation.resume(throwing: CancellationError())
    }

    /// Release one permit for `driverId`, handing the slot to the next waiter if any.
    public func release(driverId: String) {
        guard var lane = lanes[driverId] else { return }
        if !lane.waiters.isEmpty {
            let next = lane.waiters.removeFirst()
            lanes[driverId] = lane
            next.continuation.resume()
        } else {
            lane.active = max(0, lane.active - 1)
            lanes[driverId] = lane
        }
    }

    /// Run `body` while holding a permit for `driverId`. When `limit` is nil the body
    /// runs ungated with no actor hop (the common, parallel-safe path).
    public func withPermit<T>(
        driverId: String,
        limit: Int?,
        timeout: Duration = .seconds(300),
        _ body: () async -> T
    ) async throws -> T {
        guard let limit else { return await body() }
        try await acquire(driverId: driverId, limit: limit, timeout: timeout)
        let result = await body()
        release(driverId: driverId)
        return result
    }

    /// Test/diagnostic: current in-flight count for a driver.
    public func activeCount(driverId: String) -> Int { lanes[driverId]?.active ?? 0 }

    /// Test/diagnostic: queued waiter count for a driver.
    public func waiterCount(driverId: String) -> Int { lanes[driverId]?.waiters.count ?? 0 }
}

/// Acquire a spawn-gate permit or return a terminal worker failure.
func acquireDriverSpawnGate(driverId: String, limit: Int) async -> WorkerRunOutcome? {
    do {
        try await DriverConcurrencyGate.shared.acquire(driverId: driverId, limit: limit)
        return nil
    } catch is CancellationError {
        return WorkerRunOutcome(status: .failed, errorKind: .cancelled, errorReason: "spawn gate cancelled")
    } catch DriverConcurrencyGateError.acquireTimedOut(let driverId) {
        return WorkerRunOutcome(
            status: .failed, errorKind: .timedOut,
            errorReason: "spawn gate timed out for \(driverId)"
        )
    } catch {
        return WorkerRunOutcome(
            status: .failed, errorKind: .timedOut,
            errorReason: "spawn gate: \(error)"
        )
    }
}
