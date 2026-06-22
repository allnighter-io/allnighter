import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Proves the per-driver spawn gate that protects fragile CLIs (agy, cursor) from
/// concurrent headless invocation — the bug the concurrency spike isolated:
/// `antigravity` deadlocks on its singleton session dir, `cursor_agent` races on
/// its per-invocation config rewrite. A limited driver must never run two spawns
/// at once; an unlimited driver must run them fully in parallel.
final class DriverConcurrencyGateTests: XCTestCase {

    /// A driver with maxConcurrentSpawns=1 serializes: peak observed concurrency is 1.
    func testLimitOneSerializesConcurrentSpawns() async {
        let gate = DriverConcurrencyGate()
        let tracker = ConcurrencyTracker()
        let id = "antigravity"

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await gate.withPermit(driverId: id, limit: 1) {
                        await tracker.enter()
                        // simulate work; yield so overlaps would be observed if they happened
                        for _ in 0..<50 { await Task.yield() }
                        await tracker.exit()
                    }
                }
            }
        }
        let peak = await tracker.peak
        XCTAssertEqual(peak, 1, "limit=1 driver must never overlap spawns (observed peak \(peak))")
        let active = await gate.activeCount(driverId: id)
        XCTAssertEqual(active, 0, "all permits released")
    }

    /// nil limit ⇒ ungated: concurrent spawns overlap (peak > 1).
    func testNilLimitRunsInParallel() async {
        let gate = DriverConcurrencyGate()
        let tracker = ConcurrencyTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await gate.withPermit(driverId: "claude_code", limit: nil) {
                        await tracker.enter()
                        for _ in 0..<50 { await Task.yield() }
                        await tracker.exit()
                    }
                }
            }
        }
        let peak = await tracker.peak
        XCTAssertGreaterThan(peak, 1, "unlimited driver should overlap (observed peak \(peak))")
    }

    /// limit=2 caps the peak at 2 while still allowing some parallelism.
    func testLimitTwoCapsAtTwo() async {
        let gate = DriverConcurrencyGate()
        let tracker = ConcurrencyTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await gate.withPermit(driverId: "x", limit: 2) {
                        await tracker.enter()
                        for _ in 0..<50 { await Task.yield() }
                        await tracker.exit()
                    }
                }
            }
        }
        let peak = await tracker.peak
        XCTAssertLessThanOrEqual(peak, 2, "limit=2 must cap concurrency (observed peak \(peak))")
    }

    /// The shipped manifests carry the spike-proven values: agy & cursor = 1; the
    /// parallel-safe CLIs stay unlimited (nil).
    func testShippedManifestConcurrencyValues() {
        let reg = DefaultConfig.registry
        XCTAssertEqual(reg.manifest(id: "antigravity")?.maxConcurrentSpawns, 1)
        XCTAssertEqual(reg.manifest(id: "cursor_agent")?.maxConcurrentSpawns, 1)
        XCTAssertNil(reg.manifest(id: "claude_code")?.maxConcurrentSpawns)
        XCTAssertNil(reg.manifest(id: "codex")?.maxConcurrentSpawns)
        XCTAssertNil(reg.manifest(id: "grok")?.maxConcurrentSpawns)
    }
}

/// Records peak simultaneous occupancy across concurrent tasks.
private actor ConcurrencyTracker {
    private(set) var current = 0
    private(set) var peak = 0
    func enter() { current += 1; peak = max(peak, current) }
    func exit() { current -= 1 }
}
