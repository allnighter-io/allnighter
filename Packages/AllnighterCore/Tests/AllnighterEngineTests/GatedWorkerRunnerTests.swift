import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class GatedWorkerRunnerTests: XCTestCase {
    private func gatedManifest(maxConcurrentSpawns: Int?) -> DriverManifest {
        var m = TestSupport.headlessManifest(id: "antigravity", command: "agy")
        m.maxConcurrentSpawns = maxConcurrentSpawns
        return m
    }

    /// A manifest with no `maxConcurrentSpawns` is ungated: passes straight through
    /// to `inner` and never stamps a `gateWaitMs`.
    func testUngatedManifestPassesThroughUntouched() async {
        let manifest = gatedManifest(maxConcurrentSpawns: nil)
        let worker = TestSupport.worker("w", driverId: "antigravity")
        let gated = GatedWorkerRunner(inner: MockWorkerInvoking.answering(["hello"]), gate: DriverConcurrencyGate())

        let result = await gated.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.status, .done)
        XCTAssertEqual(result.output, "hello")
        XCTAssertNil(result.timing.gateWaitMs)
    }

    /// Two seats on a `maxConcurrentSpawns: 1` driver serialize: the first runs
    /// immediately (near-zero wait), the second queues behind it and its recorded
    /// `gateWaitMs` reflects that queueing.
    func testSerializesAndRecordsWaitForQueuedSeat() async {
        let manifest = gatedManifest(maxConcurrentSpawns: 1)
        let worker = TestSupport.worker("w", driverId: "antigravity")
        let gate = DriverConcurrencyGate()
        let slowInner = MockWorkerInvoking.answering(["first"], perEventDelay: .milliseconds(150))
        let fastInner = MockWorkerInvoking.answering(["second"])
        let gatedA = GatedWorkerRunner(inner: slowInner, gate: gate)
        let gatedB = GatedWorkerRunner(inner: fastInner, gate: gate)
        let invocationA = WorkerInvocation(model: worker, manifest: manifest, prompt: "a")
        let invocationB = WorkerInvocation(model: worker, manifest: manifest, prompt: "b")

        async let resultA = gatedA.collect(invocationA)
        try? await Task.sleep(for: .milliseconds(30)) // let A acquire the lane first
        async let resultB = gatedB.collect(invocationB)
        let (a, b) = await (resultA, resultB)

        XCTAssertEqual(a.status, .done)
        XCTAssertEqual(b.status, .done)
        let waitA = a.timing.gateWaitMs ?? -1
        let waitB = b.timing.gateWaitMs ?? -1
        XCTAssertGreaterThanOrEqual(waitA, 0)
        XCTAssertLessThan(waitA, 60)
        XCTAssertGreaterThan(waitB, waitA)
    }

    /// After a gated run settles, its permit is released — the lane goes back to
    /// zero active holders so the next seat never queues behind a stale permit.
    func testGateReleasesAfterCompletion() async {
        let manifest = gatedManifest(maxConcurrentSpawns: 1)
        let worker = TestSupport.worker("w", driverId: "antigravity")
        let gate = DriverConcurrencyGate()
        let gated = GatedWorkerRunner(inner: MockWorkerInvoking.answering(["done"]), gate: gate)

        _ = await gated.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        let active = await gate.activeCount(driverId: "antigravity")
        let waiters = await gate.waiterCount(driverId: "antigravity")
        XCTAssertEqual(active, 0)
        XCTAssertEqual(waiters, 0)
    }
}
