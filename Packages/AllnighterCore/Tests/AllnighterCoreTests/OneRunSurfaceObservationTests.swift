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

    /// Exact three-key observation contract (One_Run_Surface §Canonical live projection).
    private static let exactObservationKeys: Set<String> = [
        "ownerState", "activityMode", "lastActivityAt",
    ]

    /// Serialized-text probe: key present and bound to JSON null (not omitted / "" / number).
    /// Accepts pretty-print spacing around `:` so CoreJSON and compact stream both pass.
    private static func serializedTextHasNullKey(_ text: String, key: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = "\"\(escaped)\"\\s*:\\s*null"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.firstMatch(in: text, range: range) != nil
    }

    private func observationObject(from data: Data) throws -> [String: Any] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["observation"] as? [String: Any], "observation block missing")
    }

    private func observationKeys(_ trj: TeamRunJSON) throws -> Set<String> {
        Set(try observationObject(from: CoreJSON.encode(trj)).keys)
    }

    /// Shape-strict: encoded observation key set is EXACTLY the three fields.
    /// Subset checks let absent lastActivityAt through; equality does not.
    private func assertExactThreeKeys(
        _ keys: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            keys, Self.exactObservationKeys,
            "observation key set must be exactly \(Self.exactObservationKeys.sorted()); got \(keys.sorted())",
            file: file, line: line
        )
    }

    private func assertThreeKeysOnly(
        _ trj: TeamRunJSON,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        assertExactThreeKeys(try observationKeys(trj), file: file, line: line)
    }

    /// ORS-P2-NULL: nil activity must serialize as the literal key with JSON null
    /// on BOTH encode paths. Inspect serialized text/keys — never encode→decode only.
    private func assertNilActivityEmitsExplicitNull(
        _ trj: TeamRunJSON,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertNil(trj.observation.lastActivityAt, file: file, line: line)

        // show --json path (CoreJSON)
        let coreData = try CoreJSON.encode(trj)
        let coreText = String(decoding: coreData, as: UTF8.self)
        // Serialized text must contain the literal key bound to JSON null
        // (pretty-print may insert spaces around `:` — match that, not struct decode).
        XCTAssertTrue(
            Self.serializedTextHasNullKey(coreText, key: "lastActivityAt"),
            "CoreJSON/show --json must emit literal key lastActivityAt with JSON null; got \(coreText)",
            file: file, line: line
        )
        let coreObs = try observationObject(from: coreData)
        assertExactThreeKeys(Set(coreObs.keys), file: file, line: line)
        XCTAssertTrue(
            coreObs["lastActivityAt"] is NSNull,
            "CoreJSON lastActivityAt must be JSON null, got \(String(describing: coreObs["lastActivityAt"]))",
            file: file, line: line
        )
        XCTAssertFalse(coreObs["lastActivityAt"] is String, "never empty string for unobserved", file: file, line: line)
        XCTAssertFalse(coreObs["lastActivityAt"] is NSNumber, "never epoch-zero number", file: file, line: line)

        // show --stream path (plain JSONEncoder via NDJSONStreamProjector)
        let streamLine = NDJSONStreamProjector.snapshotLine(teamRunId: trj.teamRun.id, teamRun: trj)
        XCTAssertTrue(
            Self.serializedTextHasNullKey(streamLine, key: "lastActivityAt"),
            "stream/show --stream must emit literal key lastActivityAt with JSON null; got \(streamLine)",
            file: file, line: line
        )
        let lineRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(streamLine.utf8)) as? [String: Any],
            file: file, line: line
        )
        let dataObj = try XCTUnwrap(lineRoot["data"] as? [String: Any], file: file, line: line)
        let envelope = try XCTUnwrap(dataObj["teamRun"] as? [String: Any], file: file, line: line)
        let streamObs = try XCTUnwrap(envelope["observation"] as? [String: Any], file: file, line: line)
        assertExactThreeKeys(Set(streamObs.keys), file: file, line: line)
        XCTAssertTrue(
            streamObs["lastActivityAt"] is NSNull,
            "stream lastActivityAt must be JSON null, got \(String(describing: streamObs["lastActivityAt"]))",
            file: file, line: line
        )

        // Both paths agree on key set.
        XCTAssertEqual(
            Set(coreObs.keys), Set(streamObs.keys),
            "show --json and show --stream observation key sets must match",
            file: file, line: line
        )
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
        // ORS-P2-NULL: nil activity still emits all three keys; lastActivityAt is null.
        try assertNilActivityEmitsExplicitNull(trj)
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

        // Round-trip contract guard: key set is EXACTLY the three, never a fourth.
        let data = try CoreJSON.encode(trj)
        let back = try CoreJSON.decode(TeamRunJSON.self, from: data)
        XCTAssertEqual(back.observation.ownerState, .dead)
        XCTAssertEqual(back.observation.activityMode, .terminalOnly)
        let keys = try observationKeys(back)
        assertExactThreeKeys(keys)
        XCTAssertFalse(keys.contains("silenceSeconds"))
        XCTAssertFalse(keys.contains("activityState"))
        XCTAssertFalse(keys.contains("phase"))
        XCTAssertFalse(keys.contains("blocker"))
        XCTAssertFalse(keys.contains("contradiction"))
    }

    /// ORS-P2-NULL: non-nil activity still yields exactly three keys on both encode paths.
    func testNonNilActivityExactThreeKeysOnBothEncodePaths() throws {
        let at = Date(timeIntervalSince1970: 1_722_556_440)
        var run = try Fixtures.run(.runInflight)
        run.lastActivityAt = at
        let driverId = "stream_driver"
        let modelId = run.workers.first?.modelId ?? "model_stream"
        let models = [model(id: modelId, driverId: driverId)]
        let manifests = [streamingManifest(id: driverId, canStream: true)]

        let trj = TeamRunJSONMapper.map(
            run, models: models, manifests: manifests,
            context: journalCtx(ownerState: .alive)
        )
        XCTAssertNotNil(trj.observation.lastActivityAt)

        let coreObs = try observationObject(from: CoreJSON.encode(trj))
        assertExactThreeKeys(Set(coreObs.keys))
        XCTAssertTrue(coreObs["lastActivityAt"] is String)

        let line = NDJSONStreamProjector.snapshotLine(teamRunId: trj.teamRun.id, teamRun: trj)
        let lineRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let dataObj = try XCTUnwrap(lineRoot["data"] as? [String: Any])
        let envelope = try XCTUnwrap(dataObj["teamRun"] as? [String: Any])
        let streamObs = try XCTUnwrap(envelope["observation"] as? [String: Any])
        assertExactThreeKeys(Set(streamObs.keys))
        XCTAssertEqual(coreObs["lastActivityAt"] as? String, streamObs["lastActivityAt"] as? String)
    }

    /// Degrade on read: older journals that omitted lastActivityAt still decode to nil.
    func testMissingLastActivityAtKeyDecodesAsNil() throws {
        let partial = """
        {"ownerState":"dead","activityMode":"incremental"}
        """
        let obs = try CoreJSON.decode(
            TeamRunJSON.Observation.self, from: Data(partial.utf8)
        )
        XCTAssertEqual(obs.ownerState, .dead)
        XCTAssertEqual(obs.activityMode, .incremental)
        XCTAssertNil(obs.lastActivityAt, "missing key on read must degrade to nil")
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

    /// ORS-P2-NULL: null is always present as JSON null — never omitted, never "", never epoch-zero.
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
        try assertNilActivityEmitsExplicitNull(trj)
    }
}
