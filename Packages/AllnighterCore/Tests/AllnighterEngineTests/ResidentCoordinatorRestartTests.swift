import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class ResidentCoordinatorRestartTests: XCTestCase {
    func testRestartRequestRoundTripsAndClears() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resident-restart-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ResidentCoordinatorRestartStore(directory: root)
        let request = ResidentCoordinatorRestartRequest(
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        )

        try store.request(request)
        XCTAssertEqual(store.load(), request)
        store.clear()
        XCTAssertNil(store.load())
    }
}
