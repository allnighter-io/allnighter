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
            fileURL: supportRoot.appendingPathComponent("Config/model_roster.json"))
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

    func testEmptyBenchModelsJSONIncludesCounselNotBareArray() throws {
        let registry = DriverRegistry([])
        let rosterURL = AllnighterSupportRoot.config.appendingPathComponent("model_roster.json")
        try ModelRosterPersistence(fileURL: rosterURL).save(ModelRosterState(enabledModelIds: []))

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
        XCTAssertTrue(json.nextActions.contains { $0.command.hasPrefix("alln route --for") })
        XCTAssertEqual(json.nextActions.first?.command, AgentFrontDoor.routeFirst.command)
        XCTAssertNotNil(json.counsel)
        XCTAssertTrue(json.counsel?.contains("route --for") == true)

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
