import XCTest
@testable import AllnighterCore

/// LR-S02b — OpenCode body on minting enable: live-tag merge + leftover-serve reclaim.
/// Fixture-only: fake catalog, fake config path, fake reclaim table — never a socket.
final class LocalRuntimeSurfaceS02bTests: XCTestCase {
    private var modelsRoot: URL!
    private var rosterURL: URL!
    private var opencodeDir: URL!
    private var opencodeConfig: URL!
    private let now = Date(timeIntervalSince1970: 1_754_000_000)

    private let tagsPayload = """
    {"models":[
      {"name":"qwen3.8:27b-mlx","capabilities":["completion","vision","tools","thinking"]},
      {"name":"gpt-oss:20b","capabilities":["completion"]}
    ]}
    """

    private let wiredWithoutNewTagJSON = """
        {
          "enabled_providers": ["opencode-go", "ollama"],
          "provider": {
            "ollama": {
              "npm": "@ai-sdk/openai-compatible",
              "name": "Ollama (local)",
              "options": { "baseURL": "http://localhost:11434/v1" },
              "models": {
                "gpt-oss:20b": { "name": "gpt-oss:20b" }
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

    func testEnableOpencodeBodyMergesLiveTagsAndReclaimsServe() throws {
        try Data(wiredWithoutNewTagJSON.utf8).write(to: opencodeConfig)
        let table = RecordingTable(
            pid: 42_424,
            command: "/usr/local/bin/opencode serve --port 4096"
        )

        let candidateID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "qwen3.8:27b-mlx")
        let assessment = try LocalRuntimeSeatMint.enable(
            candidateID: candidateID,
            bodyDriverId: "opencode",
            snapshot: snapshotFromPayload(),
            now: now,
            opencodeConfigURL: opencodeConfig,
            serveReclaimTable: table.table,
            isTestHost: true
        )

        XCTAssertTrue(assessment.permitsEnable)
        XCTAssertTrue(assessment.disclosures.contains { $0.contains("Allnighter has not tested this model") })
        XCTAssertTrue(
            assessment.disclosures.contains { $0.contains("qwen3.8:27b-mlx") && $0.contains("OpenCode can now use") },
            assessment.disclosures.joined(separator: " | ")
        )
        XCTAssertTrue(
            assessment.disclosures.contains { $0.contains("Recycled leftover opencode serve") },
            assessment.disclosures.joined(separator: " | ")
        )
        XCTAssertEqual(table.terminated, [42_424])

        let seatedID = OllamaLocalModelDiscoveryProvider.seatedID(
            tag: "qwen3.8:27b-mlx", bodyDriverId: "opencode")
        let persisted = try XCTUnwrap(ModelCatalog.get(seatedID))
        XCTAssertEqual(persisted.origin, .discovered)
        XCTAssertEqual(persisted.driverId, "opencode")
        XCTAssertTrue(ModelCatalog.isEnabled(seatedID))

        let root = try OpenCodeOllamaProviderMerge.parseRoot(Data(contentsOf: opencodeConfig))
        let inspection = OpenCodeOllamaProviderMerge.inspect(root)
        XCTAssertEqual(inspection.ollamaModelIds, ["gpt-oss:20b", "qwen3.8:27b-mlx"])
    }

    func testEnableOpencodeBodyReportsRefusedAllnServeHonestly() throws {
        try Data(wiredWithoutNewTagJSON.utf8).write(to: opencodeConfig)
        let table = RecordingTable(pid: 99_001, command: "/usr/local/bin/alln serve")

        let candidateID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "qwen3.8:27b-mlx")
        let assessment = try LocalRuntimeSeatMint.enable(
            candidateID: candidateID,
            bodyDriverId: "opencode",
            snapshot: snapshotFromPayload(),
            now: now,
            opencodeConfigURL: opencodeConfig,
            serveReclaimTable: table.table,
            isTestHost: true
        )

        XCTAssertTrue(
            assessment.disclosures.contains { $0.contains("alln serve") && $0.contains("not stopping") },
            assessment.disclosures.joined(separator: " | ")
        )
        XCTAssertTrue(table.terminated.isEmpty)
    }

    func testEnableClaudeCodeBodyDoesNotWriteOpenCodeConfig() throws {
        try Data(wiredWithoutNewTagJSON.utf8).write(to: opencodeConfig)
        let before = try Data(contentsOf: opencodeConfig)

        let candidateID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "qwen3.8:27b-mlx")
        _ = try LocalRuntimeSeatMint.enable(
            candidateID: candidateID,
            bodyDriverId: "claude_code",
            snapshot: snapshotFromPayload(),
            now: now,
            opencodeConfigURL: opencodeConfig,
            isTestHost: true
        )

        let after = try Data(contentsOf: opencodeConfig)
        XCTAssertEqual(after, before)

        let seatedID = OllamaLocalModelDiscoveryProvider.seatedID(
            tag: "qwen3.8:27b-mlx", bodyDriverId: "claude_code")
        XCTAssertEqual(ModelCatalog.get(seatedID)?.origin, .discovered)
        XCTAssertEqual(ModelCatalog.get(seatedID)?.driverId, "claude_code")
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
}

private final class RecordingTable: @unchecked Sendable {
    let pid: Int32?
    let command: String
    private let lock = NSLock()
    private(set) var terminated: [Int32] = []

    init(pid: Int32?, command: String) {
        self.pid = pid
        self.command = command
    }

    var table: OpenCodeLeftoverServeReclaim.Table {
        OpenCodeLeftoverServeReclaim.Table(
            listenerPID: { [pid] _ in pid },
            commandLine: { [command] _ in command },
            terminate: { [weak self] victim in
                self?.lock.lock()
                self?.terminated.append(victim)
                self?.lock.unlock()
            }
        )
    }
}
