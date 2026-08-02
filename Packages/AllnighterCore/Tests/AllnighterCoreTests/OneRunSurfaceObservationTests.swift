import XCTest
import AgentOSTeam
@testable import AllnighterCore

/// ORS-S01a — three-field `observation` projection fixtures.
///
/// Contract guard: the block is exactly `ownerState`, `activityMode`, `lastActivityAt`.
/// Inference bans: owner and activity are independent; terminalOnly + nil activity is healthy.
final class OneRunSurfaceObservationTests: XCTestCase {

    // MARK: - Helpers

    private func journalCtx(
        ownerState: TeamRunJSON.Observation.OwnerState = .unknown
    ) -> TeamRunJSONMapper.Context {
        .init(ownerState: ownerState)
    }

    private func model(id: String, driverId: String) -> Model {
        Model(id: id, displayName: id, modelLabel: id, driverId: driverId)
    }

    private func streamingManifest(id: String, canStream: Bool) -> DriverManifest {
        DriverManifest(
            id: id,
            displayName: id,
            kind: .headlessCLI,
            streaming: canStream
                ? .init(supported: true, mode: .jsonlStdout)
                : .init(supported: false, mode: .none)
        )
    }

    private func observationKeys(_ trj: TeamRunJSON) throws -> Set<String> {
        let data = try CoreJSON.encode(trj)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let obs = try XCTUnwrap(root["observation"] as? [String: Any], "observation block missing")
        return Set(obs.keys)
    }

    private func assertThreeKeysOnly(_ trj: TeamRunJSON, file: StaticString = #filePath, line: UInt = #line) throws {
        let keys = try observationKeys(trj)
        let allowed: Set<String> = ["ownerState", "activityMode", "lastActivityAt"]
        XCTAssertTrue(
            keys.isSubset(of: allowed),
            "observation must not grow a fourth key; got \(keys.sorted())",
            file: file, line: line
        )
        XCTAssertTrue(keys.contains("ownerState"), file: file, line: line)
        XCTAssertTrue(keys.contains("activityMode"), file: file, line: line)
        // lastActivityAt may be absent-or-null when nil (CoreJSON / Codable style).
        if trj.observation.lastActivityAt != nil {
            XCTAssertTrue(keys.contains("lastActivityAt"), file: file, line: line)
        }
        XCTAssertEqual(keys.subtracting(allowed), [], "no fourth key", file: file, line: line)
    }

    // MARK: - Fixtures

    /// Streaming-capable driver, live owner, real lastActivityAt → {alive, incremental, date}.
    func testIncrementalProjectsAliveStreamingWithActivity() throws {
        var run = try Fixtures.run(.runInflight)
        let at = Date(timeIntervalSince1970: 1_722_556_440) // 2024-08-01T20:14:00Z
        run.lastActivityAt = at
        let driverId = "stream_driver"
        let modelId = run.workers.first?.modelId ?? "model_stream"
        let models = [model(id: modelId, driverId: driverId)]
        let manifests = [streamingManifest(id: driverId, canStream: true)]

        let trj = TeamRunJSONMapper.map(
            run, models: models, manifests: manifests,
            context: journalCtx(ownerState: .alive)
        )

        XCTAssertEqual(trj.observation.ownerState, .alive)
        XCTAssertEqual(trj.observation.activityMode, .incremental)
        XCTAssertEqual(trj.observation.lastActivityAt, at)
        try assertThreeKeysOnly(trj)
    }

    /// Non-streaming driver, live owner, NO activity yet → {alive, terminalOnly, nil}.
    /// Named negative proof: silence is not stuck; owner stays alive.
    func testTerminalOnlyLiveOwnerWithNoActivityIsHealthy() throws {
        var run = try Fixtures.run(.runInflight)
        run.lastActivityAt = nil
        let driverId = "batch_driver"
        let modelId = run.workers.first?.modelId ?? "model_batch"
        let models = [model(id: modelId, driverId: driverId)]
        let manifests = [streamingManifest(id: driverId, canStream: false)]

        let trj = TeamRunJSONMapper.map(
            run, models: models, manifests: manifests,
            context: journalCtx(ownerState: .alive)
        )

        XCTAssertEqual(
            trj.observation.ownerState, .alive,
            "null lastActivityAt must not downgrade ownerState"
        )
        XCTAssertEqual(trj.observation.activityMode, .terminalOnly)
        XCTAssertNil(
            trj.observation.lastActivityAt,
            "dead-owner/silence arithmetic must not invent activity"
        )
        // Explicit health assertion: this combination is not a defect.
        XCTAssertEqual(
            trj.observation,
            TeamRunJSON.Observation(
                ownerState: .alive, activityMode: .terminalOnly, lastActivityAt: nil),
            "activityMode: terminalOnly + lastActivityAt: nil is a healthy state"
        )
        try assertThreeKeysOnly(trj)
    }

    /// No ownership fact supplied → ownerState unknown is emitted, never silently alive/omitted.
    func testUnknownOwnerEmitsUnknownNeverAliveOrOmitted() throws {
        var run = try Fixtures.run(.runInflight)
        run.lastActivityAt = Date(timeIntervalSince1970: 1_700_000_000)
        let driverId = "stream_driver"
        let modelId = run.workers.first?.modelId ?? "model_stream"
        let models = [model(id: modelId, driverId: driverId)]
        let manifests = [streamingManifest(id: driverId, canStream: true)]

        // Default Context.ownerState is .unknown — no ownership fact supplied.
        let trj = TeamRunJSONMapper.map(
            run, models: models, manifests: manifests,
            context: journalCtx()
        )

        XCTAssertEqual(trj.observation.ownerState, .unknown)
        XCTAssertNotEqual(trj.observation.ownerState, .alive)
        XCTAssertEqual(trj.observation.activityMode, .incremental)
        XCTAssertNotNil(trj.observation.lastActivityAt)

        let data = try CoreJSON.encode(trj)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let obs = try XCTUnwrap(root["observation"] as? [String: Any], "observation must not be omitted")
        XCTAssertEqual(obs["ownerState"] as? String, "unknown")
        try assertThreeKeysOnly(trj)
    }

    /// Settled (terminal) run still projects all three observation fields.
    func testTerminalSettledRunStillProjectsThreeFields() throws {
        var run = try Fixtures.run(.runComplete)
        XCTAssertTrue(run.status.isTerminal, "fixture must be terminal")
        run.lastActivityAt = Date(timeIntervalSince1970: 1_722_556_440)
        let driverId = "batch_driver"
        let modelId = run.workers.first?.modelId ?? "model_batch"
        let models = [model(id: modelId, driverId: driverId)]
        let manifests = [streamingManifest(id: driverId, canStream: false)]

        let trj = TeamRunJSONMapper.map(
            run, models: models, manifests: manifests,
            context: journalCtx(ownerState: .dead)
        )

        XCTAssertEqual(trj.teamRun.status, .done)
        XCTAssertEqual(trj.observation.ownerState, .dead)
        XCTAssertEqual(trj.observation.activityMode, .terminalOnly)
        XCTAssertNotNil(trj.observation.lastActivityAt)
        try assertThreeKeysOnly(trj)

        // Round-trip contract guard: keys ⊆ the three, never a fourth.
        let data = try CoreJSON.encode(trj)
        let back = try CoreJSON.decode(TeamRunJSON.self, from: data)
        XCTAssertEqual(back.observation.ownerState, .dead)
        XCTAssertEqual(back.observation.activityMode, .terminalOnly)
        let keys = try observationKeys(back)
        XCTAssertTrue(keys.isSubset(of: ["ownerState", "activityMode", "lastActivityAt"]))
        XCTAssertFalse(keys.contains("silenceSeconds"))
        XCTAssertFalse(keys.contains("activityState"))
        XCTAssertFalse(keys.contains("phase"))
        XCTAssertFalse(keys.contains("blocker"))
        XCTAssertFalse(keys.contains("contradiction"))
    }
}
