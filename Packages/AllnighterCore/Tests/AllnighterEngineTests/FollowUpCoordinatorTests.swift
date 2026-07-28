import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// The Try Fix chain end to end (Try_Fix_Auto_Implement): a Bug Hunt answer run whose writer
/// emits a fenced fix-packet, the danger-not-doubt gate, and ONE child execution run that tries
/// the top hypothesis — with the two runs linked diagnosis <-> fix-attempt. Uses a mock CLI so
/// the writer's synthesis (the run plan) carries the packet block.
final class FollowUpCoordinatorTests: XCTestCase {

    /// A Bug Packet writer's output: human markdown + the EXACT fenced block the parser lifts.
    private let writerOutput = """
    # Bug Packet — paste drops images

    The reader reads the string flavor before the image flavor.

    ```fix-packet
    {
      "symptom": "pasting an image into the composer drops it",
      "truthOwner": "ComposerPasteboardReader",
      "seam": "AppKit↔SwiftUI",
      "hypotheses": [
        {"id": "h1", "cause": "string flavor read first", "fix": "read image flavor before string", "fixBoundary": "ComposerPasteboardReader.read()"}
      ],
      "proofMethod": "userObservation",
      "confidenceOrdering": "low",
      "dangerFlags": []
    }
    ```
    """

    private func makeService(repo: URL) -> RunService {
        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_composer_25"]))
        let probe = ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        return RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: writerOutput, exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] })
    }

    func testTryFixRunsChildAndLinksBothRuns() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("followup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let service = makeService(repo: repo)
        let coordinator = FollowUpCoordinator(runService: service)
        let request = RunRequest(
            message: "pasting an image into the composer drops it",
            repoRoot: repo.path, presetId: "code_bug_hunt",
            executorTeamId: "build_slice")

        let result = await coordinator.runTryFix(request, origin: .cli)
        guard case .success(let outcome) = result else { return XCTFail("chain failed: \(result)") }

        // Parent diagnosis completed and the packet was lifted from its writer output.
        XCTAssertEqual(outcome.parentRun.status, .complete)
        XCTAssertEqual(outcome.packet?.truthOwner, "ComposerPasteboardReader")

        // Doubt does not block: a low-confidence packet still runs.
        XCTAssertEqual(outcome.gate, .allowed(topHypothesisId: "h1"))

        // The child fix-attempt ran on the executor team and tried the top hypothesis.
        let child = try XCTUnwrap(outcome.childRun, "expected a child fix-attempt run")
        XCTAssertEqual(child.presetId, "build_slice")
        XCTAssertEqual(child.status, .complete)

        // Linked both ways, durably.
        XCTAssertEqual(child.parentRunId, outcome.parentRun.id)
        XCTAssertTrue(child.runLinks.contains { $0.kind == .diagnosisOf && $0.runId == outcome.parentRun.id })
        XCTAssertTrue(outcome.parentRun.runLinks.contains { $0.kind == .fixAttemptFor && $0.runId == child.id })
    }

    func testNoPacketMeansNoChild() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("followup-nopacket-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        // A bench whose writer produces prose with no fenced fix-packet block.
        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_composer_25"]))
        let probe = ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: "No structured packet here.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] })

        let coordinator = FollowUpCoordinator(runService: service)
        let request = RunRequest(
            message: "something is wrong", repoRoot: repo.path, presetId: "code_bug_hunt",
            executorTeamId: "build_slice")

        let result = await coordinator.runTryFix(request, origin: .cli)
        guard case .success(let outcome) = result else { return XCTFail("chain failed: \(result)") }

        XCTAssertNil(outcome.childRun, "no packet -> no fix attempt")
        XCTAssertEqual(outcome.gate, .blocked(code: "TRY_FIX_PACKET_MISSING",
                                              reason: "answer run produced no typed fix packet"))
    }
}
