import XCTest
@testable import AllnighterCore

final class ChromeCatalogTests: XCTestCase {
    func testFirstSliceIdsAreStableAndPresent() {
        let json = ChromeCatalog.project()
        let ids = json.actions.map(\.id)
        XCTAssertEqual(Set(ids), Set(ChromeCatalog.firstSliceIds))
        XCTAssertEqual(ids.count, ChromeCatalog.firstSliceIds.count)
    }

    func testControlLabelsAreImportedChromeCopyNotEssays() {
        let json = ChromeCatalog.project()
        let byId = Dictionary(uniqueKeysWithValues: json.actions.map { ($0.id, $0) })
        XCTAssertEqual(byId["boost_window"]?.controlLabel, ChromeCopy.boostWindow)
        XCTAssertEqual(byId["default_model"]?.controlLabel, ChromeCopy.defaultModel)
        XCTAssertEqual(byId["use_from_cli"]?.controlLabel, ChromeCopy.useFromCLI)
        XCTAssertEqual(byId["ask_ai"]?.controlLabel, ChromeCopy.askAI)
        XCTAssertEqual(byId["models"]?.controlLabel, ChromeCopy.models)
        XCTAssertEqual(byId["teams"]?.controlLabel, ChromeCopy.teams)
        XCTAssertTrue(byId["boost_window"]?.facts.contains(ChromeCopy.boostHeadline) == true)
        XCTAssertFalse(
            json.actions.contains { $0.facts.contains(where: { $0.contains("alln boost-window set") }) },
            "catalog must not teach CLI flag essays"
        )
    }

    func testScreenFilterPutsBoostFirstAndDropsHomeOnlyRows() {
        let json = ChromeCatalog.project(screen: ChromeScreen.settingsBoost.rawValue)
        XCTAssertEqual(json.actions.map(\.id), ["boost_window"])
        XCTAssertEqual(json.screen, "settings.boost")
    }

    func testSettingsPrefixIncludesEverySettingsRow() {
        let json = ChromeCatalog.project(screen: "settings")
        let ids = Set(json.actions.map(\.id))
        XCTAssertTrue(ids.contains("boost_window"))
        XCTAssertTrue(ids.contains("about_path"))
        XCTAssertTrue(ids.contains("default_model"))
        XCTAssertFalse(ids.contains("ask_ai"))
    }

    func testLiveBoostAndBenchFactsAreProjectedNotAuthored() {
        let live = ChromeLiveFacts(
            boostEnabled: false,
            boostWindowStart: "8:00 AM",
            benchChromeLabel: "6 ready · 2 need a step",
            benchReady: 6,
            benchNeedsStep: 2,
            benchSupported: 8,
            pathStandaloneHome: "/tmp/alln",
            pathResolved: nil,
            pathConflict: false
        )
        let json = ChromeCatalog.project(live: live)
        let boost = json.actions.first { $0.id == "boost_window" }
        XCTAssertTrue(boost?.facts.contains("On this Mac: Off") == true)
        XCTAssertTrue(boost?.facts.contains("Window start: 8:00 AM") == true)
        let bench = json.actions.first { $0.id == "bench_health" }
        XCTAssertEqual(bench?.controlLabel, "6 ready · 2 need a step")
        XCTAssertTrue(bench?.facts.contains { $0.contains("6 ready") } == true)
        let about = json.actions.first { $0.id == "about_path" }
        XCTAssertTrue(about?.facts.contains("\(ChromeCopy.resolvesTo): \(ChromeCopy.notOnPATH)") == true)
    }

    func testUnknownScreenReturnsNoRows() {
        let json = ChromeCatalog.project(screen: "not.a.surface")
        XCTAssertTrue(json.actions.isEmpty)
    }

    func testEncodeRoundTripUsesWhereKey() throws {
        let raw = try ChromeCatalog.encode(ChromeCatalog.project())
        XCTAssertTrue(raw.contains("\"where\""))
        XCTAssertFalse(raw.contains("whereInApp"))
        let decoded = try CoreJSON.decode(ChromeCatalogJSON.self, from: Data(raw.utf8))
        XCTAssertEqual(decoded.actions.count, ChromeCatalog.firstSliceIds.count)
    }
}
