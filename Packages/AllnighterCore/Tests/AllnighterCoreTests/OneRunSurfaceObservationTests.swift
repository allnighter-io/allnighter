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
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(trj.observation.lastActivityAt, f.string(from: at))
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

    // MARK: - Wire format (ORS-P1-DATE)

    /// Measurement rule: assert the *encoded* JSON value, not encode→decode equality.
    /// A Date-typed field round-trips under any symmetric strategy; the live stream
    /// path (`NDJSONStreamProjector.encodeLine`) uses a plain `JSONEncoder` and
    /// previously emitted `timeIntervalSinceReferenceDate` numbers while every
    /// sibling timestamp on TeamRunJSON is an ISO8601 string.
    func testLastActivityAtEncodedJSONIsISO8601StringMatchingSibling() throws {
        let at = Date(timeIntervalSince1970: 1_722_556_440) // 2024-08-01T20:14:00Z
        var run = try Fixtures.run(.runInflight)
        run.createdAt = at
        run.lastActivityAt = at
        let driverId = "stream_driver"
        let modelId = run.workers.first?.modelId ?? "model_stream"
        let models = [model(id: modelId, driverId: driverId)]
        let manifests = [streamingManifest(id: driverId, canStream: true)]

        let trj = TeamRunJSONMapper.map(
            run, models: models, manifests: manifests,
            context: journalCtx(ownerState: .alive)
        )

        // Stream path is the live Works Test surface (plain JSONEncoder — no date strategy).
        // data.teamRun is the full TeamRunJSON envelope (observation + nested RunInfo).
        let line = NDJSONStreamProjector.snapshotLine(teamRunId: trj.teamRun.id, teamRun: trj)
        let lineRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let dataObj = try XCTUnwrap(lineRoot["data"] as? [String: Any])
        let envelope = try XCTUnwrap(dataObj["teamRun"] as? [String: Any], "snapshot must carry TeamRunJSON")
        let obs = try XCTUnwrap(envelope["observation"] as? [String: Any])
        let runInfo = try XCTUnwrap(envelope["teamRun"] as? [String: Any], "RunInfo nested under TeamRunJSON.teamRun")

        let isoPattern = try NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#)
        func matchesISO(_ s: String) -> Bool {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            return isoPattern.firstMatch(in: s, range: range) != nil
        }

        // Must be a STRING on the wire — not a number (Apple epoch / Unix).
        XCTAssertTrue(
            obs["lastActivityAt"] is String,
            "observation.lastActivityAt must be a JSON string, got \(type(of: obs["lastActivityAt"] as Any)) value=\(String(describing: obs["lastActivityAt"]))"
        )
        XCTAssertFalse(obs["lastActivityAt"] is NSNumber, "must not encode as a number")
        let activity = try XCTUnwrap(obs["lastActivityAt"] as? String)
        XCTAssertTrue(
            matchesISO(activity),
            "observation.lastActivityAt must match ISO8601 ^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$, got \(activity)"
        )

        // Same formatter as sibling timestamps — cannot drift.
        let created = try XCTUnwrap(runInfo["createdAt"] as? String)
        XCTAssertTrue(matchesISO(created), "sibling createdAt format broke: \(created)")
        XCTAssertEqual(
            activity, created,
            "lastActivityAt must equal createdAt when both project the same instant"
        )
        XCTAssertEqual(activity, trj.teamRun.createdAt)

        // CoreJSON / show --json path must match the same wire shape.
        let coreData = try CoreJSON.encode(trj)
        let coreRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: coreData) as? [String: Any])
        let coreObs = try XCTUnwrap(coreRoot["observation"] as? [String: Any])
        XCTAssertEqual(coreObs["lastActivityAt"] as? String, activity)
    }

    /// Null stays JSON null (or key absent) — never "" and never epoch-zero.
    func testLastActivityAtNullStaysNullInEncodedJSON() throws {
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
        XCTAssertNil(trj.observation.lastActivityAt)

        let line = NDJSONStreamProjector.snapshotLine(teamRunId: trj.teamRun.id, teamRun: trj)
        let lineRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let dataObj = try XCTUnwrap(lineRoot["data"] as? [String: Any])
        let envelope = try XCTUnwrap(dataObj["teamRun"] as? [String: Any])
        let obs = try XCTUnwrap(envelope["observation"] as? [String: Any])

        if obs.keys.contains("lastActivityAt") {
            XCTAssertTrue(obs["lastActivityAt"] is NSNull, "nil must encode as JSON null, not a string/number")
            XCTAssertFalse(obs["lastActivityAt"] is String, "never empty string for unobserved")
            XCTAssertFalse(obs["lastActivityAt"] is NSNumber, "never epoch-zero number")
        }

        let coreData = try CoreJSON.encode(trj)
        let coreRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: coreData) as? [String: Any])
        let coreObs = try XCTUnwrap(coreRoot["observation"] as? [String: Any])
        if coreObs.keys.contains("lastActivityAt") {
            XCTAssertTrue(coreObs["lastActivityAt"] is NSNull)
        }
    }
}
