import Foundation
import XCTest
import AllnighterCore

final class QuitBackgroundReminderTests: XCTestCase {
    func testBoostOffReturnsNil() {
        XCTAssertNil(QuitBackgroundReminder.evaluate(
            boostEnabled: false,
            boostWindowStart: 8 * 60,
            suppressed: false
        ))
    }

    func testSuppressedReturnsNilEvenWhenBoostOn() {
        XCTAssertNil(QuitBackgroundReminder.evaluate(
            boostEnabled: true,
            boostWindowStart: 8 * 60,
            suppressed: true
        ))
    }

    func testBoostOnIncludesSeedTime() throws {
        let reminder = QuitBackgroundReminder.evaluate(
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
