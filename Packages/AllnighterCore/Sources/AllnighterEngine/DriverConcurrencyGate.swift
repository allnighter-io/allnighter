import Foundation

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

    private struct Lane {
        let limit: Int
        var active = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private var lanes: [String: Lane] = [:]

    public init() {}

    /// Acquire one permit for `driverId`. Returns immediately when a slot is free,
    /// otherwise suspends FIFO until a holder releases. `limit` is clamped to ≥1; the
    /// first acquire for a driver fixes its lane limit.
    public func acquire(driverId: String, limit: Int) async {
        let cap = max(1, limit)
        var lane = lanes[driverId] ?? Lane(limit: cap)
        if lane.active < lane.limit {
            lane.active += 1
            lanes[driverId] = lane
            return
        }
        // At capacity: queue. The releasing task hands its slot directly to us
        // (active stays at limit across the handoff), so no double-count.
        lanes[driverId] = lane
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lanes[driverId]?.waiters.append(cont)
        }
    }

    /// Release one permit for `driverId`, handing the slot to the next waiter if any.
    public func release(driverId: String) {
        guard var lane = lanes[driverId] else { return }
        if !lane.waiters.isEmpty {
            let next = lane.waiters.removeFirst()
            lanes[driverId] = lane
            next.resume() // slot transfers; active unchanged
        } else {
            lane.active = max(0, lane.active - 1)
            lanes[driverId] = lane
        }
    }

    /// Run `body` while holding a permit for `driverId`. When `limit` is nil the body
    /// runs ungated with no actor hop (the common, parallel-safe path).
    public func withPermit<T>(driverId: String, limit: Int?, _ body: () async -> T) async -> T {
        guard let limit else { return await body() }
        await acquire(driverId: driverId, limit: limit)
        let result = await body()
        release(driverId: driverId)
        return result
    }

    /// Test/diagnostic: current in-flight count for a driver.
    public func activeCount(driverId: String) -> Int { lanes[driverId]?.active ?? 0 }
}
