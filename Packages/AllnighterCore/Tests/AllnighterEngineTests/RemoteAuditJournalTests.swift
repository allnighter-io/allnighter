import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteAuditJournalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-audit-journal-\(UUID().uuidString)", isDirectory: true)
    }

    func testRecordAppendsEnvelopeMetadataOnly() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteAuditJournal(fileURL: root.appendingPathComponent("remote_audit.jsonl"))
        let envelope = Self.envelope(requestId: "req_1", now: now)

        try journal.record(envelope)

        let entries = try journal.entries()
        XCTAssertEqual(entries, [
            RemoteAuditJournalEntry(
                accountId: "acct_1",
                macAgentId: "mac_1",
                requestId: "req_1",
                recordedAt: now,
                auditEvent: envelope.auditEvent
            )
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.fileURL.path))
    }

    func testEntriesAreBoundedAndOrdered() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteAuditJournal(fileURL: root.appendingPathComponent("remote_audit.jsonl"))

        try journal.record(Self.envelope(requestId: "req_1", now: now))
        try journal.record(Self.envelope(requestId: "req_2", now: now.addingTimeInterval(1)))
        try journal.record(Self.envelope(requestId: "req_3", now: now.addingTimeInterval(2)))

        XCTAssertEqual(try journal.entries().map(\.requestId), ["req_1", "req_2", "req_3"])
        XCTAssertEqual(try journal.entries(limit: 2).map(\.requestId), ["req_1", "req_2"])
        XCTAssertEqual(try journal.entries(limit: 0), [])
    }

    func testAuditLineSchemaDoesNotGrowContentFields() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteAuditJournal(fileURL: root.appendingPathComponent("remote_audit.jsonl"))

        try journal.record(Self.envelope(requestId: "req_privacy", now: now))

        let raw = try String(contentsOf: journal.fileURL, encoding: .utf8)
        let line = try XCTUnwrap(raw.split(separator: "\n").first)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["accountId", "auditEvent", "macAgentId", "recordedAt", "requestId"])
        let auditObject = try XCTUnwrap(object["auditEvent"] as? [String: Any])
        XCTAssertEqual(
            Set(auditObject.keys),
            ["commandKind", "deviceId", "outcome", "requestId", "targetSummary", "ts"]
        )
        for forbidden in ["body", "raw", "content", "prompt", "output"] {
            XCTAssertFalse(object.keys.contains(forbidden))
            XCTAssertFalse(auditObject.keys.contains(forbidden))
        }
    }

    func testConcurrentRecordsRemainReadable() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteAuditJournal(fileURL: root.appendingPathComponent("remote_audit.jsonl"))
        let fixedNow = now

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    try? journal.record(Self.envelope(requestId: "req_\(index)", now: fixedNow))
                }
            }
        }

        let entries = try journal.entries()
        XCTAssertEqual(entries.count, 20)
        XCTAssertEqual(Set(entries.map(\.requestId)).count, 20)
    }

    private static func envelope(requestId: String, now: Date) -> RemoteCommandAckEnvelope {
        let audit = RemoteAuditEvent(
            ts: now,
            deviceId: "device_1",
            commandKind: .stopAll,
            requestId: requestId,
            targetSummary: "stopAll terminated=1",
            outcome: .accepted
        )
        return RemoteCommandAckEnvelope(
            requestId: requestId,
            accountId: "acct_1",
            macAgentId: "mac_1",
            ack: CommandAck(
                requestId: requestId,
                accepted: true,
                reason: nil,
                outcome: .accepted,
                serverTime: now,
                signature: "sig"
            ),
            auditEvent: audit,
            createdAt: now
        )
    }
}
