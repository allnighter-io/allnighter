import XCTest
@testable import AllnighterEngine
import AllnighterCore

final class RelayPersistenceDoctorCheckTests: XCTestCase {
    func testDoctorCheckOkWhenAllRelaysDecode() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-doctor-\(UUID().uuidString)", isDirectory: true)
        let store = RelayStateStore(rootDirectory: root)
        let state = RelayState(
            id: "relay_ok",
            projectRoot: "/tmp/repo",
            docPath: "docs/spec.md",
            pmModelId: "caller",
            devModelId: "model_dev",
            status: .awaitingPM,
            createdAt: Date()
        )
        _ = try store.save(state)

        let check = RelayPersistenceDoctorCheck.doctorCheck(relaysRoot: root)
        XCTAssertEqual(check.name, "relayPersistence")
        XCTAssertEqual(check.status, .ok)
    }

    func testDoctorCheckCriticalWhenRetiredWorkerKeysPresent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-doctor-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("relay_bad", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {
          "id": "relay_bad",
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

        let check = RelayPersistenceDoctorCheck.doctorCheck(relaysRoot: root)
        XCTAssertEqual(check.status, .critical)
        XCTAssertEqual(check.name, "relayPersistence")
        XCTAssertTrue(check.detail.contains("relay_bad"))
    }
}
