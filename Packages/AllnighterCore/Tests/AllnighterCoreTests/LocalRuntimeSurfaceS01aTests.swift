import XCTest
@testable import AllnighterCore

/// LR-S01a — `/api/tags` capabilities filter + list-time overlay.
/// Fixture-only: never opens a socket, never writes the real catalog.
final class LocalRuntimeSurfaceS01aTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_754_000_000)
    private let registry = DriverRegistry([
        DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
        DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
    ])
    private let paid = ModelDefinition(
        id: "model_lr_s01a_paid_fixture",
        displayName: "Paid fixture",
        modelLabel: "opus",
        driverId: "claude_code",
        role: .answerer,
        origin: .builtIn,
        defaultEnabled: true,
        capabilities: ModelCapabilities()
    )
    private let seatedLocal = ModelDefinition(
        id: "custom_claude_code_qwen38_27b_local",
        displayName: "Qwen seated",
        modelLabel: "ollama/qwen3.8:27b-mlx",
        driverId: "claude_code",
        role: .answerer,
        origin: .custom,
        defaultEnabled: true,
        capabilities: ModelCapabilities()
    )

    /// Completion + declared embedding (no completion) + no capabilities field.
    private let tagsPayload = """
    {"models":[
      {"name":"qwen3.8:27b-mlx","capabilities":["completion","vision","tools","thinking"]},
      {"name":"nomic-embed-text","capabilities":["embedding"]},
      {"name":"nomic-shaped-orphan"}
    ]}
    """

    func testParseTagsKeepsCapabilitiesAndDoesNotNameHeuristic() throws {
        let tags = try XCTUnwrap(OllamaLocalRuntimeObserver.parseTags(Data(tagsPayload.utf8)))
        XCTAssertEqual(tags.map(\.name), [
            "qwen3.8:27b-mlx", "nomic-embed-text", "nomic-shaped-orphan",
        ])
        XCTAssertEqual(tags[0].capabilities, ["completion", "vision", "tools", "thinking"])
        XCTAssertTrue(tags[0].isCompletionCandidate)
        XCTAssertFalse(tags[0].capabilityUnknown)

        XCTAssertEqual(tags[1].capabilities, ["embedding"])
        XCTAssertFalse(tags[1].isCompletionCandidate)
        XCTAssertFalse(tags[1].capabilityUnknown)

        XCTAssertNil(tags[2].capabilities)
        XCTAssertTrue(tags[2].isCompletionCandidate)
        XCTAssertTrue(tags[2].capabilityUnknown)
    }

    func testDeclaredEmptyCapabilitiesAreHiddenNotUnknown() throws {
        let json = #"{"models":[{"name":"embed-only","capabilities":[]}]}"#
        let tags = try XCTUnwrap(OllamaLocalRuntimeObserver.parseTags(Data(json.utf8)))
        XCTAssertEqual(tags.first?.capabilities, [])
        XCTAssertFalse(tags.first?.isCompletionCandidate ?? true)
        XCTAssertFalse(tags.first?.capabilityUnknown ?? true)
    }

    func testDiscoveryResultDropsDeclaredNonCompletionAndKeepsUnknown() {
        let snapshot = snapshotFromPayload()
        let result = OllamaLocalModelDiscoveryProvider.result(from: snapshot, discoveredAt: now)
        XCTAssertEqual(result.candidates.map(\.displayName), [
            "qwen3.8:27b-mlx", "nomic-shaped-orphan",
        ])
        XCTAssertFalse(result.candidates.contains { $0.displayName == "nomic-embed-text" })
        XCTAssertTrue(result.candidates.allSatisfy { $0.origin == .discovered })
        XCTAssertTrue(result.candidates.allSatisfy { !$0.defaultEnabled })
    }

    func testProjectorOverlaysDiscoveredNotSeatedAndOmitsAvailable() throws {
        let list = ModelListProjector.build(
            registry: registry,
            definitions: [paid],
            probeRecords: [],
            now: now,
            diagnostics: [],
            ollamaLocal: snapshotFromPayload()
        )
        XCTAssertTrue(list.nextActions.isEmpty, "overlay must not use list-level nextActions")

        let completionID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "qwen3.8:27b-mlx")
        let unknownID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "nomic-shaped-orphan")
        let embedID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "nomic-embed-text")

        let completion = try XCTUnwrap(list.models.first { $0.id == completionID })
        let unknown = try XCTUnwrap(list.models.first { $0.id == unknownID })
        XCTAssertNil(list.models.first { $0.id == embedID })

        try assertOverlayRow(
            completion,
            expectedCommand: OllamaLocalModelDiscoveryProvider.enableCommand(
                candidateID: completionID),
            capabilityUnknown: false
        )
        try assertOverlayRow(
            unknown,
            expectedCommand: OllamaLocalModelDiscoveryProvider.enableCommand(
                candidateID: unknownID),
            capabilityUnknown: true
        )

        let paidRow = try XCTUnwrap(list.models.first { $0.id == paid.id })
        XCTAssertNil(paidRow.discovered)
        XCTAssertNil(paidRow.seated)
        XCTAssertNil(paidRow.readiness)
        XCTAssertNil(paidRow.enableCommand)
        let paidKeys = try encodedKeys(paidRow)
        XCTAssertFalse(paidKeys.contains("discovered"))
        XCTAssertFalse(paidKeys.contains("seated"))
        XCTAssertFalse(paidKeys.contains("readiness"))
        XCTAssertFalse(paidKeys.contains("enableCommand"))
    }

    func testSeatedTagIsNotDuplicatedAndKeepsLawAvailable() throws {
        let list = ModelListProjector.build(
            registry: registry,
            definitions: [paid, seatedLocal],
            probeRecords: [],
            now: now,
            diagnostics: [],
            ollamaLocal: snapshotFromPayload()
        )
        let completionID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "qwen3.8:27b-mlx")
        XCTAssertNil(list.models.first { $0.id == completionID })

        let seated = try XCTUnwrap(list.models.first { $0.id == seatedLocal.id })
        XCTAssertEqual(seated.readiness, "Available")
        XCTAssertEqual(seated.seated, true)
        XCTAssertEqual(seated.discovered, true)
        XCTAssertNil(seated.enableCommand)
        XCTAssertNotEqual(seated.origin, "discovered")
    }

    func testUnparseableCapabilitiesStayVisibleUnknown() throws {
        let json = #"{"models":[{"name":"weird","capabilities":"completion"}]}"#
        let tags = try XCTUnwrap(OllamaLocalRuntimeObserver.parseTags(Data(json.utf8)))
        XCTAssertNil(tags.first?.capabilities)
        XCTAssertTrue(tags.first?.isCompletionCandidate ?? false)
        XCTAssertTrue(tags.first?.capabilityUnknown ?? false)
    }

    // MARK: - Helpers

    private func snapshotFromPayload() -> OllamaLocalRuntimeObserver.Snapshot {
        let tags = OllamaLocalRuntimeObserver.parseTags(Data(tagsPayload.utf8))!
        return OllamaLocalRuntimeObserver.snapshot(
            observedAt: now,
            ollamaVersion: "0.32.12",
            localTags: tags,
            residentModels: []
        )
    }

    private func assertOverlayRow(
        _ row: ModelListJSON.Entry,
        expectedCommand: String,
        capabilityUnknown: Bool
    ) throws {
        XCTAssertEqual(row.discovered, true)
        XCTAssertEqual(row.seated, false)
        XCTAssertFalse(row.enabled)
        XCTAssertFalse(row.ready)
        XCTAssertEqual(row.origin, "discovered")
        XCTAssertEqual(row.state, "available")
        XCTAssertNotEqual(row.readiness, "Available")
        XCTAssertNil(row.readiness)
        XCTAssertEqual(row.enableCommand, expectedCommand)
        XCTAssertTrue(expectedCommand.hasPrefix("alln models enable "))
        XCTAssertTrue(expectedCommand.contains("--body opencode"))

        let object = try encoded(row)
        XCTAssertNil(object["readiness"])
        XCTAssertEqual(object["discovered"] as? Bool, true)
        XCTAssertEqual(object["seated"] as? Bool, false)
        XCTAssertEqual(object["enableCommand"] as? String, expectedCommand)
        if capabilityUnknown {
            XCTAssertEqual(row.capabilityUnknown, true)
            XCTAssertEqual(object["capabilityUnknown"] as? Bool, true)
        } else {
            XCTAssertNil(row.capabilityUnknown)
            XCTAssertNil(object["capabilityUnknown"])
        }
    }

    private func encoded(_ entry: ModelListJSON.Entry) throws -> [String: Any] {
        let data = try CoreJSON.encode(entry)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encodedKeys(_ entry: ModelListJSON.Entry) throws -> Set<String> {
        Set(try encoded(entry).keys)
    }
}
