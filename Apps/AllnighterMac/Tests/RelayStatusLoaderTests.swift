import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// ATL-S04 — status chrome reads the same projection as `alln loop status --json`.
@MainActor
final class RelayStatusLoaderTests: XCTestCase {
    func testLoadLoopJSONMatchesStoreFields() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-relay-status-\(UUID().uuidString)", isDirectory: true)
        let relays = root.appendingPathComponent("relays", isDirectory: true)
        let store = LoopStateStore(rootDirectory: relays)
        let id = "relay_status_fixture"
        let state = LoopState(
            id: id,
            projectRoot: "/tmp/project",
            docPath: "docs/spec.md",
            pmModelId: "model_pm",
            devModelId: "model_dev",
            status: .running,
            rounds: [
                RelayRound(roundNumber: 1, baselineHead: "aaa", startedAt: Date(), outcome: .continued)
            ],
            createdAt: Date(),
            note: "Round 1 in flight"
        )
        try store.save(state)

        let json = try XCTUnwrap(RelayStatusLoader.loadLoopJSON(loopId: id, stateStore: store, threadProjector: nil))
        XCTAssertEqual(json.relayId, id)
        XCTAssertEqual(json.status, "running")
        XCTAssertEqual(json.rounds, 1)
        XCTAssertEqual(json.note, "Round 1 in flight")
        XCTAssertEqual(RelayStatusLoader.statusCommand(loopId: id), "alln loop status \(id) --json")
    }
}
