import Foundation
import XCTest
import AllnighterCore

final class BoostSeatEligibilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testCatalogMapsOpenCodeGoToOpencodeSeed() {
        XCTAssertEqual(
            BoostSeatCatalog.seedDriverId(forCapacitySource: "opencode_go"),
            "opencode"
        )
        XCTAssertEqual(
            BoostSeatCatalog.seedDriverId(forCapacitySource: "kimi"),
            "kimi"
        )
        XCTAssertEqual(
            BoostSeatCatalog.seedDriverId(forCapacitySource: "agy"),
            "antigravity"
        )
    }

    func testFiveHourAndSessionAreBoostScopes() {
        XCTAssertTrue(BoostSeatEligibility.isBoostWindowScope(.fiveHour))
        XCTAssertTrue(BoostSeatEligibility.isBoostWindowScope(.session))
        XCTAssertFalse(BoostSeatEligibility.isBoostWindowScope(.weekly))
        XCTAssertFalse(BoostSeatEligibility.isBoostWindowScope(.monthly))
    }

    func testEligibilityFromClaudeSessionAndKimiFiveHour() {
        let windows = [
            CapacityWindow(
                used: 10,
                source: "claude_code",
                scope: .session,
                resetAt: now.addingTimeInterval(3600),
                resetPrecision: .minute,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
            CapacityWindow(
                used: 5,
                source: "kimi",
                scope: .fiveHour,
                resetAt: now.addingTimeInterval(3600),
                resetPrecision: .minute,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
            CapacityWindow(
                used: 40,
                source: "kimi",
                scope: .weekly,
                resetAt: now.addingTimeInterval(86400),
                resetPrecision: .day,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "codex",
                scope: .fiveHour,
                observedAt: now,
                sourceTier: .onDisk
            ),
        ]
        let eligible = BoostSeatEligibility.eligibleSeedDriverIds(windows: windows)
        XCTAssertEqual(eligible, Set(["claude_code", "kimi"]))
    }

    func testOpenCodeGoEvidenceUnlocksOpencodeSeat() {
        let windows = [
            CapacityWindow(
                used: 12,
                source: "opencode_go",
                scope: .fiveHour,
                resetAt: now.addingTimeInterval(7200),
                resetPrecision: .minute,
                observedAt: now,
                sourceTier: .dashboardScrape
            )
        ]
        XCTAssertEqual(
            BoostSeatEligibility.eligibleSeedDriverIds(windows: windows),
            Set(["opencode"])
        )
    }

    func testWeeklyOnlyDoesNotUnlock() {
        let windows = [
            CapacityWindow(
                used: 10,
                source: "codex",
                scope: .weekly,
                resetAt: now.addingTimeInterval(86400),
                resetPrecision: .day,
                observedAt: now,
                sourceTier: .onDisk
            )
        ]
        XCTAssertTrue(BoostSeatEligibility.eligibleSeedDriverIds(windows: windows).isEmpty)
    }

    func testProviderBuilderFiltersToEligibleCatalogSeats() {
        let settings = BoostWindowSettings(
            enabled: true,
            appliesTo: ["claude_code", "kimi", "opencode"]
        )
        let providers = BoostWindowProviderBuilder.providerStates(
            settings: settings,
            manifests: [],
            models: [],
            readyDriverIds: ["claude_code", "kimi"],
            probeRecords: [],
            eligibleSeedDriverIds: ["claude_code", "kimi", "opencode"]
        )
        XCTAssertEqual(providers.map(\.id), ["claude_code", "kimi", "opencode"])
        XCTAssertTrue(providers.allSatisfy(\.included))
    }

    func testNormalizeDropsUnknownAppliesTo() {
        var s = BoostWindowSettings(appliesTo: ["claude_code", "not_a_driver", "kimi"])
        s.normalize()
        XCTAssertEqual(s.appliesTo, ["claude_code", "kimi"])
    }
}
