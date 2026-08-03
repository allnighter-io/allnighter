import XCTest
@testable import AllnighterCore
@testable import AllnighterCLI

/// QABC-S00d — capacity injected into the menu/bootstrap envelopes from the
/// CLI layer, with the no-probe-on-read law enforced at the seam.
final class MenuCapacityInjectionCLITests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_753_833_600)

    private final class CountingProbeExecutor: CapacityProbeExecuting, @unchecked Sendable {
        private let lock = NSLock()
        private var _callCount = 0
        var callCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _callCount
        }
        func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
            lock.lock(); _callCount += 1; lock.unlock()
            return [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: request.now),
                    source: request.source,
                    scope: .weekly,
                    observedAt: request.now,
                    sourceTier: .tuiProbe
                ),
            ]
        }
    }

    func testMenuCapacitySpawnsZeroProbes() {
        let executor = CountingProbeExecutor()
        _ = AllnighterCLI.menuCapacity(now: now, probeExecutor: executor)
        XCTAssertEqual(executor.callCount, 0, "reading the menu must never spawn a probe (QABC-S00 law)")
    }

    func testMenuCapacityIsOmittedUntilResidentTrustGate() {
        let capacity = AllnighterCLI.menuCapacity(now: now)
        XCTAssertNil(capacity, "menu capacity stays omitted until the Resident trust gate (CWB-S00b)")
    }

    func testMenuShowModelDetailCarriesOnlyMatchingSourceRow() throws {
        let capacity = MenuJSON.Capacity(
            generatedAt: now,
            rows: [
                MenuJSON.Capacity.Row(
                    source: "claude_code",
                    effectiveRemainingPercent: 61,
                    resetAt: nil,
                    scope: .weekly,
                    shortRemainingPercent: 61,
                    observedAgeSeconds: 120,
                    unknownReason: nil
                ),
                MenuJSON.Capacity.Row(
                    source: "codex",
                    effectiveRemainingPercent: 10,
                    resetAt: nil,
                    scope: .weekly,
                    shortRemainingPercent: 10,
                    observedAgeSeconds: 240,
                    unknownReason: nil
                ),
            ]
        )

        let menu = MenuCatalog.project(capacity: capacity)
        let claudeModel = try XCTUnwrap(menu.models.first(where: { $0.driverId == "claude_code" }))

        let detail = try MenuCatalog.show(ref: claudeModel.ref, capacity: capacity)
        let model = try XCTUnwrap(detail.model)
        let rows = try XCTUnwrap(model.capacity?.rows)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.source, "claude_code")
    }

    func testMenuShowModelDetailCapacityNilWhenNoRowMatches() throws {
        let capacity = MenuJSON.Capacity(
            generatedAt: now,
            rows: [
                MenuJSON.Capacity.Row(
                    source: "codex",
                    effectiveRemainingPercent: 10,
                    resetAt: nil,
                    scope: .weekly,
                    shortRemainingPercent: 10,
                    observedAgeSeconds: 240,
                    unknownReason: nil
                ),
            ]
        )

        let menu = MenuCatalog.project(capacity: capacity)
        let claudeModel = try XCTUnwrap(menu.models.first(where: { $0.driverId == "claude_code" }))

        let detail = try MenuCatalog.show(ref: claudeModel.ref, capacity: capacity)
        let model = try XCTUnwrap(detail.model)
        XCTAssertNil(model.capacity)
    }
}
