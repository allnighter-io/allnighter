import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

/// S01c (RLR-L8): the legacy-journal policy is **MAP** — every on-disk
/// `RunStatus` value present today decodes and projects unambiguously via
/// `RunStatus.lifecycle`. The one thing that must never happen is inventing a
/// status for an unmappable journal: an unknown/legacy `status` raw string in
/// an EXISTING run.json must surface as a typed `JOURNAL_CORRUPT` distinct
/// from "no run.json at all" (`RUN_NOT_FOUND`), never silently coerced and
/// never treated as if the run never existed.
final class LegacyJournalTests: XCTestCase {

    private func tempStore() -> (RunStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("legacy-journal-\(UUID().uuidString)")
        return (RunStore(rootDirectory: dir), dir)
    }

    private func run(_ id: String, status: RunStatus) -> TeamRun {
        TeamRun(id: id, prompt: "p", status: status,
                workers: [Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
                workerAnswers: [TeamAnswer(memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                                           result: WorkerRunResult(status: status.isTerminal ? .done : .running))],
                createdAt: Date())
    }

    private func writeRawStatus(_ raw: String, runId: String, in store: RunStore) throws {
        // Start from a real, fully-valid encode of a terminal run so every OTHER
        // field is well-formed — the only thing under test is the `status` value
        // — then patch just the status raw string with a plain text substitution
        // (mirrors an on-disk journal written by an older/removed status case).
        let valid = run(runId, status: .complete)
        var text = String(decoding: try CoreJSON.encode(valid), as: UTF8.self)
        // CoreJSON pretty-prints (space around `:`), so match the quoted value
        // alone rather than assuming compact `"status":"complete"` spacing.
        text = text.replacingOccurrences(of: "\"complete\"", with: "\"\(raw)\"")
        let directory = try store.runDirectory(forRunId: runId)
        try Data(text.utf8).write(to: directory.appendingPathComponent("run.json"))
    }

    // MARK: - legacy-decode matrix (Part 1.6 on-disk sample: complete/failed/fanning_out/partial)

    func testLegacyStatusValuesDecodeAndProjectToExpectedLifecycle() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cases: [(RunStatus, RunLifecycle)] = [
            (.complete, .done),
            (.failed, .failed),
            (.fanningOut, .running),
            (.partial, .done),
        ]
        for (status, expectedLifecycle) in cases {
            let id = "legacy-\(status.rawValue)"
            try store.save(run(id, status: status), models: [])

            // loadRawResult must succeed (no corruption) for every value present
            // in the real 159-journal sample.
            switch store.loadRawResult(runId: id) {
            case .success(let loaded?):
                XCTAssertEqual(loaded.status, status)
                XCTAssertEqual(loaded.status.lifecycle, expectedLifecycle, "status \(status.rawValue) must project to \(expectedLifecycle)")
            case .success(nil):
                XCTFail("expected a decoded run for \(status.rawValue), got no journal")
            case .failure(let error):
                XCTFail("expected \(status.rawValue) to decode cleanly, got \(error)")
            }

            // loadRaw/load stay the swallow-to-optional facade callers already use.
            XCTAssertEqual(store.loadRaw(runId: id)?.status, status)
        }
    }

    // MARK: - unknown status raw string → JOURNAL_CORRUPT, never RUN_NOT_FOUND, never invented

    func testUnknownStatusRawStringSurfacesAsCorruptNotNotFound() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeRawStatus("some_removed_legacy_status_value", runId: "unmappable", in: store)

        switch store.loadRawResult(runId: "unmappable") {
        case .success:
            XCTFail("an unknown status raw string must never decode successfully (that would be silent invention)")
        case .failure(let error):
            guard case .corrupt(let runId, let detail) = error else {
                XCTFail("expected .corrupt"); return
            }
            XCTAssertEqual(runId, "unmappable")
            XCTAssertFalse(detail.isEmpty)
        }

        // The swallow-to-optional facade must still return nil (never crash, never
        // invent a status) — but the DISTINCT signal lives in loadRawResult, which
        // CLI call sites consult before falling back to a bare RUN_NOT_FOUND.
        XCTAssertNil(store.loadRaw(runId: "unmappable"))
        XCTAssertNil(store.load(runId: "unmappable"))
    }

    func testMissingJournalIsNotFoundNotCorrupt() {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // No run.json was ever written for this id — this is RUN_NOT_FOUND
        // territory, distinct from an existing-but-corrupt journal.
        switch store.loadRawResult(runId: "never-existed") {
        case .success(let run):
            XCTAssertNil(run)
        case .failure(let error):
            XCTFail("a directory/file that was never created is RUN_NOT_FOUND, not corrupt: \(error)")
        }
        XCTAssertNil(store.loadRaw(runId: "never-existed"))
        XCTAssertNil(store.load(runId: "never-existed"))
    }

    // MARK: - clock defaults (RLR-L8): named, finite, S01-only (no enforcement)

    func testClockDefaultsAreNamedAndFinite() {
        XCTAssertEqual(RunClockDefaults.handshakeTimeoutSeconds, 60)
        XCTAssertEqual(RunClockDefaults.firstActivityTimeoutSeconds, 120)
        XCTAssertEqual(RunClockDefaults.wallTimeoutSeconds, 3600)
        XCTAssertTrue(RunClockDefaults.allFinite)
        // First-activity gives headroom over the handshake bound; wall exceeds
        // the longest driver-manifest idle timeout (1800s) so it never
        // pre-empts a healthy long run (RLR-L8 rationale).
        XCTAssertGreaterThan(RunClockDefaults.firstActivityTimeoutSeconds, RunClockDefaults.handshakeTimeoutSeconds)
        XCTAssertGreaterThan(RunClockDefaults.wallTimeoutSeconds, 1800)
    }
}
