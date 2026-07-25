import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// A handed-off run must be the run the caller asked for.
///
/// The mailbox used to carry four of `RunRequest`'s ~26 fields, so the app ran a
/// DIFFERENT request than the one typed: a founder's `--effort low` team came back
/// at default effort, and context, attachments and every timeout override were
/// dropped with no warning anywhere.
final class HandoffPayloadFidelityTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-fidelity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Every field on `RunRequest` is either carried through the mailbox or listed
    /// here as a deliberate omission WITH a reason. A new field defaults to neither,
    /// so adding one to `RunRequest` fails this test until someone decides — which
    /// is the point: silent loss is exactly how `--effort` went missing.
    func testEveryRunRequestFieldIsCarriedOrConsciouslyOmitted() {
        let carried: Set<String> = [
            "message", "repoRoot", "threadId", "projectId", "presetId", "workerId",
            "effort", "lane", "type", "context", "deliveries", "executorTeamId",
            "advisoryReview", "workerTimeoutSeconds", "handshakeTimeoutSeconds",
            "firstActivityTimeoutSeconds", "wallTimeoutSeconds", "spawnConcurrencyLimit",
            "commitMessage", "noCommit", "proofCommand", "proofTimeoutSeconds",
            "retryOf", "acceptSurvivors",
        ]
        let omittedOnPurpose: [String: String] = [
            "timing": "a caller-seeded clock ladder for the CALLER's process; the "
                + "host's run measures itself and must not report times that never "
                + "happened here",
            "idempotencyKey": "the local attempt that triggered the hand-off may hold "
                + "it, so re-using it would make the host refuse its own work as a "
                + "duplicate of the run it is replacing",
        ]

        let fields = Set(Mirror(reflecting: RunRequest(message: "m", repoRoot: "/tmp"))
            .children.compactMap(\.label))
        XCTAssertFalse(fields.isEmpty, "reflection found no fields — the gate would be vacuous")

        let unaccounted = fields.subtracting(carried).subtracting(omittedOnPurpose.keys)
        XCTAssertTrue(
            unaccounted.isEmpty,
            "RunRequest gained \(unaccounted.sorted()) — carry it through "
            + "SandboxHandoffSpool.Request, or add it to omittedOnPurpose WITH a reason. "
            + "A field that is neither is silently dropped on every hand-off.")

        // And the omission list must not rot into a list of things that no longer exist.
        let staleOmissions = Set(omittedOnPurpose.keys).subtracting(fields)
        XCTAssertTrue(staleOmissions.isEmpty, "no longer real fields: \(staleOmissions.sorted())")
    }

    /// The specific loss a founder hit: `--effort low` handed off as default effort.
    func testEffortAndContextSurviveTheMailbox() throws {
        let spool = SandboxHandoffSpool(
            directory: tmp.appendingPathComponent("Handoff", isDirectory: true))
        let original = RunRequest(
            message: "Run the TEST team only.",
            repoRoot: "/repo",
            threadId: "thread_1",
            presetId: "custom_test_pipe",
            effort: .low,
            context: "extra context the worker needs",
            wallTimeoutSeconds: 900,
            noCommit: true)

        try spool.enqueue(.init(
            runId: "handoff-fidelity", message: original.message, repoRoot: original.repoRoot,
            presetId: original.presetId, workerId: original.workerId,
            effort: original.effort, context: original.context,
            threadId: original.threadId, wallTimeoutSeconds: original.wallTimeoutSeconds,
            noCommit: original.noCommit))

        let readBack = try XCTUnwrap(try spool.unclaimed().first).runRequest

        XCTAssertEqual(readBack.effort, .low, "the founder asked for low effort")
        XCTAssertEqual(readBack.context, "extra context the worker needs")
        XCTAssertEqual(readBack.threadId, "thread_1")
        XCTAssertEqual(readBack.wallTimeoutSeconds, 900)
        XCTAssertTrue(readBack.noCommit)
        XCTAssertEqual(readBack.presetId, "custom_test_pipe")
    }
}
