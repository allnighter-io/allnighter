import XCTest
import AllnighterCore
import AgentOSCLI
@testable import AllnighterEngine

/// `ProbeFreshnessDisclosure` (AllnighterCore) cannot import
/// `RunCapabilityClock` (AllnighterEngine) — Core sits below Engine in the
/// dependency graph — so it carries a duplicated `"RunService"` literal to
/// recognize a run-sourced record. This locks the two together: if either
/// side's literal drifts, `evidenceSource` silently stops saying `"run"` and
/// nothing else would catch it (it is disclosure, not a hard failure).
final class RunCapabilityClockAttributionTests: XCTestCase {
    func testRunCapabilityClockResolvedByMatchesTheDisclosureLiteral() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let manifest = DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI)
        let merged = try XCTUnwrap(RunCapabilityClock.apply(
            driverId: "kimi", manifest: manifest,
            result: WorkerRunResult(status: .done, output: "ok"), now: now, records: []))
        let record = try XCTUnwrap(merged.first { $0.driverId == "kimi" })

        let registry = DriverRegistry([manifest])
        let list = DriverListProjector.build(
            registry: registry, probeRecords: [record], now: now, models: [], parkedDriverIds: [])
        let row = try XCTUnwrap(list.drivers.first)

        XCTAssertEqual(record.resolvedBy, RunCapabilityClock.resolvedBy)
        XCTAssertEqual(row.freshness.evidenceSource, "run",
                        "a run-sourced record must disclose evidenceSource \"run\", never \"probe\"")
    }
}
