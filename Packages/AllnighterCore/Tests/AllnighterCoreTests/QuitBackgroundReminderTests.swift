import Foundation
import XCTest
import AllnighterCore

final class QuitBackgroundReminderTests: XCTestCase {
    func testBothOffReturnsNil() {
        XCTAssertNil(QuitBackgroundReminder.evaluate(
            capacityEnabled: false,
            boostEnabled: false,
            boostWindowStart: 8 * 60,
            suppressed: false
        ))
    }

    func testSuppressedReturnsNilEvenWhenFeaturesOn() {
        XCTAssertNil(QuitBackgroundReminder.evaluate(
            capacityEnabled: true,
            boostEnabled: true,
            boostWindowStart: 8 * 60,
            suppressed: true
        ))
    }

    func testCapacityOnly() {
        let reminder = QuitBackgroundReminder.evaluate(
            capacityEnabled: true,
            boostEnabled: false,
            boostWindowStart: 8 * 60,
            suppressed: false
        )
        XCTAssertEqual(reminder?.bullets.count, 1)
        XCTAssertEqual(
            reminder?.bullets.first,
            "Capacity stays warm for alln only while this app is open."
        )
    }

    func testBoostOnlyIncludesSeedTime() throws {
        let reminder = QuitBackgroundReminder.evaluate(
            capacityEnabled: false,
            boostEnabled: true,
            boostWindowStart: 8 * 60,
            suppressed: false
        )
        XCTAssertEqual(reminder?.bullets.count, 1)
        let bullet = try XCTUnwrap(reminder?.bullets.first)
        XCTAssertTrue(bullet.contains("Boost is on"))
        XCTAssertTrue(
            bullet.contains(BoostWindowTiming.formatMinutes(BoostWindowTiming.seedFiresAt(8 * 60))),
            "expected seed time in: \(bullet)"
        )
        XCTAssertTrue(bullet.contains("Mac awake"))
        XCTAssertFalse(bullet.lowercased().contains("app is open"),
                       "Boost must not teach leaving the app open")
    }

    func testBothFeaturesTwoBullets() throws {
        let reminder = QuitBackgroundReminder.evaluate(
            capacityEnabled: true,
            boostEnabled: true,
            boostWindowStart: 8 * 60,
            suppressed: false
        )
        XCTAssertEqual(reminder?.bullets.count, 2)
        let text = try XCTUnwrap(reminder?.informativeText)
        XCTAssertTrue(text.contains("• Capacity"))
        XCTAssertTrue(text.contains("• Boost"))
    }

    func testPersistenceRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("quit-reminder-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = QuitBackgroundReminderPersistence(fileURL: file)
        XCTAssertFalse(store.loadSuppressed())
        try store.saveSuppressed(true)
        XCTAssertTrue(store.loadSuppressed())
        try store.saveSuppressed(false)
        XCTAssertFalse(store.loadSuppressed())
    }
}
