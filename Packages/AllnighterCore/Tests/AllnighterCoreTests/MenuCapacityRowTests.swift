import XCTest
@testable import AllnighterCore

/// QABC-S00b — the lean `MenuJSON.Capacity` decision row, narrowed purely
/// from `CapacityStripJSONRow` (one derivation path with `alln capacity`).
final class MenuCapacityRowTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_753_833_600)

    private func stripRow(
        source: String = "claude",
        dashboardRemainingPercent: Double? = 74.22,
        dashboardScope: CapacityWindowScope? = .weekly,
        dashboardResetAt: Date? = nil,
        shortRemainingPercent: Double? = 61.9,
        effectiveRemainingPercent: Double? = 61.9,
        observedAgeSeconds: Double? = 818.8028600215912,
        unknownReason: CapacityStripUnknownKind? = nil
    ) -> CapacityStripJSONRow {
        CapacityStripJSONRow(
            source: source,
            displayName: source.capitalized,
            planTier: nil,
            color: .neutral,
            dashboardRemainingPercent: dashboardRemainingPercent,
            dashboardScope: dashboardScope,
            dashboardResetAt: dashboardResetAt,
            shortRemainingPercent: shortRemainingPercent,
            shortWindowNone: false,
            effectiveRemainingPercent: effectiveRemainingPercent,
            observedAt: observedAgeSeconds.map { now.addingTimeInterval(-$0) },
            observedAgeSeconds: observedAgeSeconds,
            unknownReason: unknownReason,
            pools: []
        )
    }

    func testNarrowingRoundsAndKeepsCoreFields() {
        let reset = now.addingTimeInterval(3600)
        let strip = CapacityStripJSON(
            contractVersion: "7.0.0",
            generatedAt: now,
            rows: [stripRow(dashboardResetAt: reset)]
        )

        let capacity = MenuJSON.Capacity(strip: strip)

        XCTAssertEqual(capacity.generatedAt, now)
        XCTAssertEqual(capacity.rows.count, 1)
        let row = capacity.rows[0]
        XCTAssertEqual(row.source, "claude")
        XCTAssertEqual(row.resetAt, reset)
        XCTAssertEqual(row.scope, .weekly)
        XCTAssertEqual(row.effectiveRemainingPercent, 62)
        XCTAssertEqual(row.shortRemainingPercent, 62)
        XCTAssertEqual(row.observedAgeSeconds, 819)
        XCTAssertNil(row.unknownReason)
    }

    func testUnknownRowSurvivesWithoutInventingAZero() {
        let strip = CapacityStripJSON(
            contractVersion: "7.0.0",
            generatedAt: now,
            rows: [
                stripRow(
                    source: "codex",
                    dashboardRemainingPercent: nil,
                    shortRemainingPercent: nil,
                    effectiveRemainingPercent: nil,
                    observedAgeSeconds: nil,
                    unknownReason: .neverSampled
                )
            ]
        )

        let row = MenuJSON.Capacity(strip: strip).rows[0]

        XCTAssertEqual(row.source, "codex")
        XCTAssertNil(row.effectiveRemainingPercent)
        XCTAssertNil(row.shortRemainingPercent)
        XCTAssertEqual(row.unknownReason, "neverSampled")
        // Never observed stays nil, never a fabricated `0` or sentinel duration.
        XCTAssertNil(row.observedAgeSeconds)
    }

    func testCompactEncodingOfRealisticSixRowCatalogStaysUnder700Bytes() throws {
        // Mirrors the founder bench mix: most sources are flat (no distinct
        // dashboard scope/reset), one is fully unknown, only one carries a
        // real weekly window — not six fully-populated rows.
        let rows = [
            stripRow(source: "claude", dashboardScope: .weekly, dashboardResetAt: now.addingTimeInterval(3600), observedAgeSeconds: 120),
            stripRow(source: "codex", dashboardRemainingPercent: nil, dashboardScope: nil, dashboardResetAt: nil, shortRemainingPercent: 0, effectiveRemainingPercent: 0, observedAgeSeconds: 240),
            stripRow(source: "cursor", dashboardScope: nil, dashboardResetAt: nil, observedAgeSeconds: 360),
            stripRow(source: "grok", dashboardScope: nil, dashboardResetAt: nil, observedAgeSeconds: 480),
            stripRow(source: "kimi", dashboardScope: nil, dashboardResetAt: nil, observedAgeSeconds: 600),
            stripRow(
                source: "antigravity",
                dashboardRemainingPercent: nil,
                dashboardScope: nil,
                dashboardResetAt: nil,
                shortRemainingPercent: nil,
                effectiveRemainingPercent: nil,
                observedAgeSeconds: nil,
                unknownReason: .neverSampled
            )
        ]
        let strip = CapacityStripJSON(contractVersion: "7.0.0", generatedAt: now, rows: rows)
        let capacity = MenuJSON.Capacity(strip: strip)

        let data = try MenuCatalog.encodeCompact(capacity)

        XCTAssertLessThan(data.count, 700, "compact 6-row capacity should stay well under the 815B pretty / 562B compact budget")
    }

    // MARK: - QABC-S00c passthrough wiring

    func testMenuCatalogProjectDefaultsCapacityToNilAndOmitsTheKey() throws {
        let menu = MenuCatalog.project()
        XCTAssertNil(menu.capacity)

        let data = try MenuCatalog.encodeCompact(menu)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // `alln capacity` is itself a registry command, so `commands` legitimately
        // contains the substring "capacity" — assert on the top-level key only.
        XCTAssertNil(object["capacity"], "top-level capacity key must be absent, not null, when uninjected")
    }

    func testMenuCatalogProjectRoundTripsInjectedCapacity() throws {
        let strip = CapacityStripJSON(
            contractVersion: "7.0.0",
            generatedAt: now,
            rows: [stripRow()]
        )
        let capacity = MenuJSON.Capacity(strip: strip)

        let menu = MenuCatalog.project(capacity: capacity)
        XCTAssertEqual(menu.capacity, capacity)

        let data = try MenuCatalog.encodeCompact(menu)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MenuJSON.self, from: data)
        XCTAssertEqual(decoded.capacity, capacity)
        XCTAssertEqual(decoded.capacity?.rows.first?.source, "claude")
    }

    func testBootstrapJSONDefaultsCapacityToNilAndPassesThroughWhenInjected() {
        let plain = Bootstrap.json(host: .generic, binaryPath: "alln", onPath: true)
        XCTAssertNil(plain.capacity)

        let strip = CapacityStripJSON(
            contractVersion: "7.0.0",
            generatedAt: now,
            rows: [stripRow(source: "codex")]
        )
        let capacity = MenuJSON.Capacity(strip: strip)
        let injected = Bootstrap.json(host: .generic, binaryPath: "alln", onPath: true, capacity: capacity)
        XCTAssertEqual(injected.capacity, capacity)
    }
}
