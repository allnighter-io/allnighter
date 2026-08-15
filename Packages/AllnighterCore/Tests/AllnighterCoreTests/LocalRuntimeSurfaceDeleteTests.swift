import XCTest
@testable import AllnighterCore

/// Delete of a seated local row unregisters that tag from a fixture
/// `opencode.json` when no remaining OpenCode seat needs it.
/// Never opens a socket. Never touches `~/.config/opencode/opencode.json`.
final class LocalRuntimeSurfaceDeleteTests: XCTestCase {
    private var modelsRoot: URL!
    private var rosterURL: URL!
    private var opencodeDir: URL!
    private var opencodeConfig: URL!
    private let now = Date(timeIntervalSince1970: 1_754_000_000)
    private let registry = DriverRegistry([
        DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
        DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
    ])

    private let tagsPayload = """
    {"models":[
      {"name":"qwen3.8:27b-mlx","capabilities":["completion","vision","tools","thinking"]},
      {"name":"smollm2:135m","capabilities":["completion"]}
    ]}
    """

    private let wiredBothTagsJSON = """
        {
          "enabled_providers": ["opencode-go", "ollama"],
          "provider": {
            "ollama": {
              "npm": "@ai-sdk/openai-compatible",
              "name": "Ollama (local)",
              "options": { "baseURL": "http://localhost:11434/v1" },
              "models": {
                "qwen3.8:27b-mlx": { "name": "qwen3.8:27b-mlx" },
                "smollm2:135m": { "name": "smollm2:135m" }
              }
            }
          }
        }
        """

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        modelsRoot = base.appendingPathComponent("models", isDirectory: true)
        rosterURL = base.appendingPathComponent("model_roster.json")
        opencodeDir = base.appendingPathComponent("opencode-config", isDirectory: true)
        opencodeConfig = opencodeDir.appendingPathComponent("opencode.json")
        try! FileManager.default.createDirectory(at: opencodeDir, withIntermediateDirectories: true)
        CatalogRoots.overrideForTesting(
            teams: base.appendingPathComponent("teams", isDirectory: true),
            skills: base.appendingPathComponent("skills", isDirectory: true),
            models: modelsRoot)
        ModelCatalog.overrideRosterForTesting(fileURL: rosterURL)
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        ModelCatalog.resetTestingOverrides()
        try? FileManager.default.removeItem(at: modelsRoot.deletingLastPathComponent())
        super.tearDown()
    }

    func testDeleteUnregistersTagAndDiscloses() throws {
        try Data(wiredBothTagsJSON.utf8).write(to: opencodeConfig)
        let seatedID = try persistDiscovered(tag: "smollm2:135m", body: "opencode")

        let outcome = try LocalRuntimeSeatDelete.delete(
            id: seatedID,
            opencodeConfigURL: opencodeConfig,
            isTestHost: true
        )

        XCTAssertNil(ModelCatalog.get(seatedID))
        XCTAssertEqual(outcome.unregisteredTags, ["smollm2:135m"])
        XCTAssertTrue(
            outcome.disclosures.contains { $0.contains("Unregistered from opencode.json: smollm2:135m") },
            outcome.disclosures.joined(separator: " | ")
        )
        XCTAssertEqual(configModelIds(), ["qwen3.8:27b-mlx"])
    }

    func testDeleteKeepsTagWhenAnotherOpenCodeSeatNeedsIt() throws {
        try Data(wiredBothTagsJSON.utf8).write(to: opencodeConfig)
        let seatedID = try persistDiscovered(tag: "smollm2:135m", body: "opencode")
        let custom = try ModelCatalog.createCustom(
            driverId: "opencode",
            displayName: "smollm2 custom",
            modelLabel: "ollama/smollm2:135m",
            role: .answerer,
            enabled: true,
            registry: registry
        )

        let outcome = try LocalRuntimeSeatDelete.delete(
            id: seatedID,
            opencodeConfigURL: opencodeConfig,
            isTestHost: true
        )

        XCTAssertNil(ModelCatalog.get(seatedID))
        XCTAssertNotNil(ModelCatalog.get(custom.id))
        XCTAssertTrue(outcome.unregisteredTags.isEmpty)
        XCTAssertTrue(outcome.disclosures.isEmpty)
        XCTAssertEqual(configModelIds(), ["qwen3.8:27b-mlx", "smollm2:135m"])

        let last = try LocalRuntimeSeatDelete.delete(
            id: custom.id,
            opencodeConfigURL: opencodeConfig,
            isTestHost: true
        )
        XCTAssertEqual(last.unregisteredTags, ["smollm2:135m"])
        XCTAssertEqual(configModelIds(), ["qwen3.8:27b-mlx"])
    }

    func testClaudeSeatDeleteUnregistersWhenNoOpenCodeSeatRemains() throws {
        try Data(wiredBothTagsJSON.utf8).write(to: opencodeConfig)
        let seatedID = try persistDiscovered(tag: "smollm2:135m", body: "claude_code")

        let outcome = try LocalRuntimeSeatDelete.delete(
            id: seatedID,
            opencodeConfigURL: opencodeConfig,
            isTestHost: true
        )

        XCTAssertEqual(outcome.unregisteredTags, ["smollm2:135m"])
        XCTAssertEqual(configModelIds(), ["qwen3.8:27b-mlx"])
    }

    func testNonLocalDeleteDoesNotTouchOpenCodeConfig() throws {
        try Data(wiredBothTagsJSON.utf8).write(to: opencodeConfig)
        let before = try Data(contentsOf: opencodeConfig)
        let custom = try ModelCatalog.createCustom(
            driverId: "opencode",
            displayName: "paid-shaped custom",
            modelLabel: "opencode/big-pickle",
            role: .answerer,
            enabled: true,
            registry: registry
        )

        let outcome = try LocalRuntimeSeatDelete.delete(
            id: custom.id,
            opencodeConfigURL: opencodeConfig,
            isTestHost: true
        )

        XCTAssertTrue(outcome.disclosures.isEmpty)
        XCTAssertTrue(outcome.unregisteredTags.isEmpty)
        XCTAssertEqual(try Data(contentsOf: opencodeConfig), before)
    }

    func testMissingConfigFileLeavesCatalogDeletedWithoutDisclosure() throws {
        let seatedID = try persistDiscovered(tag: "smollm2:135m", body: "opencode")
        XCTAssertFalse(FileManager.default.fileExists(atPath: opencodeConfig.path))

        let outcome = try LocalRuntimeSeatDelete.delete(
            id: seatedID,
            opencodeConfigURL: opencodeConfig,
            isTestHost: true
        )

        XCTAssertNil(ModelCatalog.get(seatedID))
        XCTAssertTrue(outcome.unregisteredTags.isEmpty)
        XCTAssertTrue(outcome.disclosures.isEmpty)
    }

    func testTestHostWithoutOverrideRefusesRealConfigAndStillDeletesSeat() throws {
        let seatedID = try persistDiscovered(tag: "smollm2:135m", body: "opencode")

        let outcome = try LocalRuntimeSeatDelete.delete(
            id: seatedID,
            opencodeConfigURL: nil,
            isTestHost: true
        )

        XCTAssertNil(ModelCatalog.get(seatedID))
        XCTAssertTrue(outcome.unregisteredTags.isEmpty)
        XCTAssertTrue(
            outcome.disclosures.contains { $0.contains("refusing to touch the real OpenCode config") },
            outcome.disclosures.joined(separator: " | ")
        )
    }

    func testEnableThenDeleteIsSymmetricOnFixtureConfig() throws {
        let wiredWithoutNewTagJSON = """
        {
          "enabled_providers": ["opencode-go", "ollama"],
          "provider": {
            "ollama": {
              "npm": "@ai-sdk/openai-compatible",
              "name": "Ollama (local)",
              "options": { "baseURL": "http://localhost:11434/v1" },
              "models": {
                "qwen3.8:27b-mlx": { "name": "qwen3.8:27b-mlx" }
              }
            }
          }
        }
        """
        try Data(wiredWithoutNewTagJSON.utf8).write(to: opencodeConfig)
        let candidateID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "smollm2:135m")
        _ = try LocalRuntimeSeatMint.enable(
            candidateID: candidateID,
            bodyDriverId: "opencode",
            snapshot: snapshotFromPayload(),
            now: now,
            opencodeConfigURL: opencodeConfig,
            isTestHost: true
        )
        XCTAssertTrue((configModelIds() ?? []).contains("smollm2:135m"))

        let seatedID = OllamaLocalModelDiscoveryProvider.seatedID(
            tag: "smollm2:135m", bodyDriverId: "opencode")
        let outcome = try LocalRuntimeSeatDelete.delete(
            id: seatedID,
            opencodeConfigURL: opencodeConfig,
            isTestHost: true
        )
        XCTAssertEqual(outcome.unregisteredTags, ["smollm2:135m"])
        XCTAssertEqual(configModelIds(), ["qwen3.8:27b-mlx"])
    }

    // MARK: - Helpers

    private func persistDiscovered(tag: String, body: String) throws -> ModelID {
        var seat = OllamaLocalModelDiscoveryProvider.candidate(for: tag, discoveredAt: now)
        seat.driverId = body
        seat.id = OllamaLocalModelDiscoveryProvider.seatedID(tag: tag, bodyDriverId: body)
        seat.origin = .discovered
        try ModelCatalog.saveDiscovered(seat)
        return seat.id
    }

    private func snapshotFromPayload() -> OllamaLocalRuntimeObserver.Snapshot {
        let tags = OllamaLocalRuntimeObserver.parseTags(Data(tagsPayload.utf8))!
        return OllamaLocalRuntimeObserver.snapshot(
            observedAt: now,
            ollamaVersion: "0.32.12",
            localTags: tags,
            residentModels: []
        )
    }

    private func configModelIds() -> [String]? {
        guard let data = try? Data(contentsOf: opencodeConfig),
              let root = try? OpenCodeOllamaProviderMerge.parseRoot(data)
        else { return nil }
        return OpenCodeOllamaProviderMerge.inspect(root).ollamaModelIds
    }
}
