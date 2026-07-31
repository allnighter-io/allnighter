import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

final class DriverParkTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("driver-park-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testParkPersistsAndUnparkClears() throws {
        let url = tmp.appendingPathComponent("cli_setup.json")
        let store = SetupStore(fileURL: url)
        var state = SetupStore.State()
        state.park("opencode")
        state.park("opencode") // idempotent
        _ = try store.save(state)

        let reloaded = store.load()
        XCTAssertEqual(reloaded.parkedDriverIds, ["opencode"])
        XCTAssertTrue(reloaded.isParked("opencode"))
        XCTAssertEqual(DriverPark.parkedSet(fileURL: url), ["opencode"])

        var next = reloaded
        next.unpark("opencode")
        _ = try store.save(next)
        XCTAssertTrue(store.load().parkedDriverIds.isEmpty)
    }

    func testLegacyFileWithoutParkedKeyDecodes() throws {
        let url = tmp.appendingPathComponent("cli_setup.json")
        try Data(#"{"records":[]}"#.utf8).write(to: url)
        let state = SetupStore(fileURL: url).load()
        XCTAssertTrue(state.parkedDriverIds.isEmpty)
    }

    func testReadyDriverIdsExcludesParked() {
        let ready = ToolProbeRecord(
            driverId: "opencode",
            status: .ready(version: "1.0"),
            lastProbeAt: .distantPast
        )
        let ids = TeamAssembler.readyDriverIds(from: [ready], excludingParked: ["opencode"])
        XCTAssertTrue(ids.isEmpty)
        XCTAssertEqual(TeamAssembler.readyDriverIds(from: [ready]), ["opencode"])
    }

    func testDriverListProjectorSortsParkedLast() {
        let registry = DriverRegistry([
            DriverManifest(id: "alpha_cli", displayName: "Alpha", kind: .headlessCLI),
            DriverManifest(id: "zeta_cli", displayName: "Zeta", kind: .headlessCLI),
        ])
        let models: [Model] = [
            Model(id: "m_a", displayName: "A", modelLabel: "a", driverId: "alpha_cli", role: .both, enabled: true),
            Model(id: "m_z", displayName: "Z", modelLabel: "z", driverId: "zeta_cli", role: .both, enabled: false),
        ]
        let list = DriverListProjector.build(
            registry: registry,
            probeRecords: [],
            models: models,
            parkedDriverIds: ["alpha_cli"]
        )
        XCTAssertEqual(list.drivers.map(\.driverId), ["zeta_cli", "alpha_cli"])
        XCTAssertEqual(list.drivers.map(\.parked), [false, true])
        XCTAssertEqual(list.drivers.map(\.status), ["notChecked", "parked"])
    }

    func testDriverListProjectorSurfacesRateLimitedDetail() {
        let reset = Date(timeIntervalSince1970: 7_200)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .structured,
            rawSnippet: "weekly",
            observedAt: .distantPast,
            observedResetAt: reset,
            wakeAfter: reset
        )
        let registry = DriverRegistry([
            DriverManifest(id: "codex", displayName: "Codex", kind: .headlessCLI),
        ])
        let models: [Model] = [
            Model(id: "m_c", displayName: "C", modelLabel: "c", driverId: "codex", role: .both, enabled: true),
        ]
        let list = DriverListProjector.build(
            registry: registry,
            probeRecords: [
                ToolProbeRecord(
                    driverId: "codex",
                    status: .rateLimited(observation: observation),
                    version: "0.9",
                    lastProbeAt: .distantPast
                ),
            ],
            models: models,
            parkedDriverIds: []
        )
        XCTAssertEqual(list.drivers.count, 1)
        let row = list.drivers[0]
        XCTAssertEqual(row.status, "notReady")
        XCTAssertEqual(row.probeDetail, DoctorReport.rateLimitedDetail(observation: observation))
        XCTAssertTrue(row.probeDetail?.contains("Rate limited") ?? false)
    }

    func testBenchReadinessExcludesParked() {
        let model = Model(
            id: "m1", displayName: "M", modelLabel: "m",
            driverId: "opencode", role: .both, enabled: true
        )
        let ready = ToolProbeRecord(
            driverId: "opencode",
            status: .ready(version: "1.0"),
            lastProbeAt: .distantPast
        )
        let on = BenchReadiness.readyModels(
            models: [model], probeRecords: [ready], parkedDriverIds: []
        )
        XCTAssertEqual(on.map(\.id), ["m1"])
        let off = BenchReadiness.readyModels(
            models: [model], probeRecords: [ready], parkedDriverIds: ["opencode"]
        )
        XCTAssertTrue(off.isEmpty)
    }

    /// Rate-limited drivers flow through readyDriverIds into bench readiness
    /// (so explicit loop dispatch can attempt and capacity-park).
    func testBenchReadinessIncludesRateLimitedDriver() {
        let model = Model(
            id: "model_gpt_sol", displayName: "GPT Sol", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .structured,
            rawSnippet: "0%",
            observedAt: .distantPast,
            wakeAfter: Date(timeIntervalSince1970: 9_000)
        )
        let limited = ToolProbeRecord(
            driverId: "codex",
            status: .rateLimited(observation: observation),
            lastProbeAt: .distantPast
        )
        let on = BenchReadiness.readyModels(
            models: [model], probeRecords: [limited], parkedDriverIds: []
        )
        XCTAssertEqual(on.map(\.id), ["model_gpt_sol"])
    }
}
