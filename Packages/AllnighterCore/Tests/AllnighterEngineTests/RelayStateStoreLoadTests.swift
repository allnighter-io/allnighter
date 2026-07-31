import XCTest
@testable import AllnighterEngine
import AllnighterCore

final class RelayStateStoreLoadTests: XCTestCase {
    func testLoadResultNotFoundWhenRelayJSONMissing() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-load-\(UUID().uuidString)", isDirectory: true)
        let store = RelayStateStore(rootDirectory: root)
        switch store.loadResult(id: "relay_missing") {
        case .failure(.notFound(let id)):
            XCTAssertEqual(id, "relay_missing")
        default:
            XCTFail("expected notFound")
        }
    }

    func testLoadResultDecodeFailedFlagsRetiredWorkerKeys() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-load-\(UUID().uuidString)", isDirectory: true)
        let store = RelayStateStore(rootDirectory: root)
        let directory = root.appendingPathComponent("relay_legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {
          "id": "relay_legacy",
          "projectRoot": "/tmp/repo",
          "docPath": "docs/spec.md",
          "pmWorkerId": "caller",
          "devWorkerId": "model_dev",
          "status": "awaitingPM",
          "pmMode": "caller",
          "rounds": [],
          "createdAt": "2026-07-29T12:00:00Z"
        }
        """
        try json.write(to: directory.appendingPathComponent("relay.json"), atomically: true, encoding: .utf8)

        switch store.loadResult(id: "relay_legacy") {
        case .failure(.decodeFailed(let detail)):
            XCTAssertTrue(detail.retiredWorkerKeys)
            XCTAssertTrue(detail.agentMessage.contains("devWorkerId"))
        default:
            XCTFail("expected decodeFailed")
        }
    }

    func testContainsRetiredWorkerKeysIgnoresProseMentions() {
        let prose = """
        {"externalSubmission":"see devWorkerId in the migration doc","devModelId":"model_dev"}
        """
        XCTAssertFalse(RelayStateStore.containsRetiredWorkerKeys(in: prose))
    }
}
