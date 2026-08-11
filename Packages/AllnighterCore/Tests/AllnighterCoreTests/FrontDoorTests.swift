import XCTest
@testable import AllnighterCore

final class FrontDoorTests: XCTestCase {
    private var supportRoot: URL!
    private var previousSupportDir: String?

    override func setUp() {
        super.setUp()
        supportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        previousSupportDir = ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"]
        setenv("ALLNIGHTER_SUPPORT_DIR", supportRoot.path, 1)
        CatalogRoots.overrideForTesting(
            teams: supportRoot.appendingPathComponent("Catalogs/teams", isDirectory: true),
            skills: supportRoot.appendingPathComponent("Catalogs/skills", isDirectory: true),
            models: supportRoot.appendingPathComponent("Catalogs/models", isDirectory: true))
        ModelCatalog.overrideRosterForTesting(
            fileURL: supportRoot
                .appendingPathComponent("Config", isDirectory: true)
                .appendingPathComponent("model_roster.json"))
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        ModelCatalog.resetTestingOverrides()
        if let previousSupportDir {
            setenv("ALLNIGHTER_SUPPORT_DIR", previousSupportDir, 1)
        } else {
            unsetenv("ALLNIGHTER_SUPPORT_DIR")
        }
        try? FileManager.default.removeItem(at: supportRoot)
        super.tearDown()
    }

    func testSupportRootHonorsEnvOverrideForRosterPath() throws {
        let rosterURL = AllnighterSupportRoot.config.appendingPathComponent("model_roster.json")
        XCTAssertTrue(rosterURL.path.hasPrefix(supportRoot.path))
        try ModelRosterPersistence(fileURL: rosterURL).save(ModelRosterState(enabledModelIds: []))
        XCTAssertNotNil(ModelRosterPersistence(fileURL: rosterURL).load())
    }

    /// Replaces `testCodexSandboxUsesStableThreadTempSupportRoot`, which locked in
    /// the deleted per-thread temp redirect. Founder ruling 2026-07-24 (CR-S05):
    /// there is ONE durable state root for every host. A restricted host that
    /// cannot write it fails honestly; it is never handed a parallel, empty
    /// product. See docs/archive/phases/CODE_RED_Core_Infrastructure_Repair.md.
    func testCodexSandboxResolvesTheOneCanonicalSupportRoot() {
        let previousSandbox = ProcessInfo.processInfo.environment["CODEX_SANDBOX"]
        let previousThreadID = ProcessInfo.processInfo.environment["CODEX_THREAD_ID"]
        unsetenv("ALLNIGHTER_SUPPORT_DIR")
        setenv("CODEX_SANDBOX", "workspace-write", 1)
        setenv("CODEX_THREAD_ID", "thread/with spaces", 1)
        defer {
            setenv("ALLNIGHTER_SUPPORT_DIR", supportRoot.path, 1)
            if let previousSandbox { setenv("CODEX_SANDBOX", previousSandbox, 1) }
            else { unsetenv("CODEX_SANDBOX") }
            if let previousThreadID { setenv("CODEX_THREAD_ID", previousThreadID, 1) }
            else { unsetenv("CODEX_THREAD_ID") }
        }

        let root = AllnighterSupportRoot.support
        XCTAssertFalse(root.path.hasPrefix(FileManager.default.temporaryDirectory.path),
                       "a sandboxed host must not get a temp state tree: \(root.path)")
        XCTAssertFalse(root.path.contains("Allnighter-Codex"), root.path)
        XCTAssertTrue(root.path.hasSuffix("/Allnighter"), root.path)
    }

    func testEmptyBenchModelsJSONIncludesCounselNotBareArray() throws {
        let registry = DriverRegistry([])
        try ModelCatalog.saveRosterForTesting(ModelRosterState(enabledModelIds: []))

        var defs = ModelCatalog.list()
        let enabled = Set(ModelCatalog.benchModels(registry: registry).map(\.id))
        defs = defs.filter { enabled.contains($0.id) }

        let json = ModelListProjector.build(
            registry: registry,
            definitions: defs,
            probeRecords: [],
            diagnostics: [],
            benchOnly: true,
            driverId: nil)

        XCTAssertTrue(json.models.isEmpty)
        XCTAssertFalse(json.nextActions.isEmpty)
        XCTAssertTrue(json.nextActions.contains { $0.command.hasPrefix("alln menu --json") })
        XCTAssertEqual(json.nextActions.first?.command, AgentFrontDoor.menuFirst.command)
        XCTAssertNotNil(json.counsel)
        XCTAssertTrue(json.counsel?.contains("menu --json") == true)

        let data = try CoreJSON.encode(json)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["nextActions"])
        XCTAssertFalse((obj?["nextActions"] as? [Any])?.isEmpty ?? true)
    }

    func testFullCatalogStillPopulatedUnderIsolatedSupportDir() {
        let registry = DriverRegistry([])
        let json = ModelListProjector.build(
            registry: registry,
            definitions: ModelCatalog.list(),
            probeRecords: [],
            diagnostics: [],
            benchOnly: false,
            driverId: nil)
        XCTAssertFalse(json.models.isEmpty)
        XCTAssertNil(json.counsel)
        XCTAssertTrue(json.nextActions.isEmpty)
    }

    func testEmptyTeamsCatalogIncludesCounsel() {
        let payload = TeamCatalogJSON.project([], lane: nil, contractVersion: ContractRegistry.contractVersion)
        XCTAssertTrue(payload.teams.isEmpty)
        XCTAssertFalse(payload.nextActions.isEmpty)
        XCTAssertNotNil(payload.counsel)
    }

    func testDoctorMissingConfigIncludesCounsel() {
        let result = DoctorReport.build(
            models: [],
            manifests: [],
            records: [],
            inputs: .init(
                binaryVersion: "0.1.0",
                contractVersion: ContractRegistry.contractVersion,
                configDirWritable: false,
                runsDirWritable: true,
                full: false))
        XCTAssertNotNil(result.counsel)
        XCTAssertEqual(result.nextActions.first?.command, "alln doctor --json")
    }
}
