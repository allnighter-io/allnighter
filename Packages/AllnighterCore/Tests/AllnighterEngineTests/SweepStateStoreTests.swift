import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class SweepStateStoreTests: XCTestCase {
    func testCheckpointRoundTripAndDeadOwner() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweep-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SweepStateStore(rootDirectory: root)
        let engine = SweepEngine(store: store)
        var state = try engine.create(
            order: "order",
            targetIds: ["one", "two"],
            projectRoot: "/tmp/proj",
            sweepId: "sw1"
        )
        XCTAssertEqual(try store.load(id: "sw1")?.targets.count, 2)
        XCTAssertFalse(store.isOwnerDead(id: "sw1"), "live test process owns a running sweep")
        XCTAssertNotNil(state.artifactPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.artifactPath ?? ""))

        state.status = .interrupted
        try store.save(state)
        XCTAssertTrue(store.isOwnerDead(id: "sw1"), "terminal save clears owner.pid")
        XCTAssertEqual(try store.load(id: "sw1")?.status, .interrupted)
    }
}
