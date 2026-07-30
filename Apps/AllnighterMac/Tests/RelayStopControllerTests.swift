import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// ATL-S04 — founder Stop from GUI routes through `RelayCoordinator.stop`.
@MainActor
final class RelayStopControllerTests: XCTestCase {
    private func tempRoot(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-relay-stop-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testCanStopRunningNotTerminal() throws {
        let root = tempRoot("running")
        let store = RelayStateStore(rootDirectory: root.appendingPathComponent("relays", isDirectory: true))
        let id = "relay_fixture_running"
        try store.save(RelayState(
            id: id,
            projectRoot: "/tmp",
            docPath: "doc.md",
            pmModelId: "pm",
            devModelId: "dev",
            status: .running,
            createdAt: Date()
        ))
        let controller = RelayStopController(stateStore: store)
        XCTAssertTrue(controller.canStop(relayId: id))
    }

    func testCannotStopFounderStopped() throws {
        let root = tempRoot("stopped")
        let store = RelayStateStore(rootDirectory: root.appendingPathComponent("relays", isDirectory: true))
        let id = "relay_fixture_stopped"
        try store.save(RelayState(
            id: id,
            projectRoot: "/tmp",
            docPath: "doc.md",
            pmModelId: "pm",
            devModelId: "dev",
            status: .stopped,
            createdAt: Date(),
            finishedAt: Date(),
            stoppedReason: RelayState.founderStoppedReason
        ))
        let controller = RelayStopController(stateStore: store)
        XCTAssertFalse(controller.canStop(relayId: id))
    }
}
