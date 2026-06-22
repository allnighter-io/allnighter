import Foundation
import AllnighterCore
import XCTest

final class BoostWindowSettingsTests: XCTestCase {
    func testTimingModelMatchesSpec() {
        let start = 8 * 60   // 08:00
        XCTAssertEqual(BoostWindowTiming.seedFiresAt(start), 5 * 60 + 30)   // 05:30
        XCTAssertEqual(BoostWindowTiming.resetMid(start), 10 * 60 + 30)     // 10:30
        XCTAssertEqual(BoostWindowTiming.windowEnd(start), 13 * 60)           // 13:00
    }

    func testSnap15() {
        XCTAssertEqual(BoostWindowTiming.snap15(481), 480)
        XCTAssertEqual(BoostWindowTiming.snap15(487), 480)
        XCTAssertEqual(BoostWindowTiming.snap15(488), 495)
    }

    func testSeedOvernightIdle() {
        XCTAssertTrue(BoostWindowTiming.seedIsOvernightIdle(5 * 60 + 30))
        XCTAssertFalse(BoostWindowTiming.seedIsOvernightIdle(15 * 60 + 30))
    }

    func testPersistenceRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("boost-\(UUID().uuidString).json")
        let p = BoostWindowSettingsPersistence(fileURL: file)
        var s = BoostWindowSettings.fresh
        s.enabled = true
        s.windowStart = 6 * 60
        s.appliesTo = ["codex", "claude_code"]
        try p.save(s)
        let loaded = p.load()
        XCTAssertTrue(loaded.enabled)
        XCTAssertEqual(loaded.windowStart, 6 * 60)
        XCTAssertEqual(Set(loaded.appliesTo), Set(["claude_code", "codex"]))
    }

    func testProjectorNoQuietRunUpWhenDaytimeSeed() {
        let settings = BoostWindowSettings(enabled: true, windowStart: 14 * 60)  // seed ~11:30a
        let providers = [
            ProviderBoostState(id: "claude_code", displayName: "Claude", connected: true, signedIn: true, included: true)
        ]
        let json = BoostWindowProjector.build(settings: settings, providers: providers, contractVersion: "test")
        XCTAssertEqual(json.displayState, BoostWindowDisplayState.noQuietRunUp.rawValue)
        XCTAssertEqual(json.bucketHeadline, "1 -> 1")
    }

    func testProjectorCalibratedWhenOvernightSeedAndResetObserved() {
        let settings = BoostWindowSettings(enabled: true, windowStart: 8 * 60)
        let providers = [
            ProviderBoostState(
                id: "claude_code", displayName: "Claude", connected: true, signedIn: true, included: true,
                lastObservedReset: Date())
        ]
        let json = BoostWindowProjector.build(settings: settings, providers: providers, contractVersion: "test")
        XCTAssertEqual(json.displayState, BoostWindowDisplayState.calibrated.rawValue)
        XCTAssertEqual(json.bucketHeadline, "1 -> 2")
    }
}
