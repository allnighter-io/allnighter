import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// Default `alln doctor` must stay quota-free and bounded — slow live probes belong
/// behind `--full` only (`Pilot_DX.md` §DX6).
final class DoctorTimingTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-doctor-timing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testDefaultDoctorProbeUsesCachedRecordsAndSkipsSlowRunner() async {
        let manifests = [
            DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
        ]
        let cached = [
            ToolProbeRecord(
                driverId: "claude_code",
                status: .installedNotProbed(version: "1.0"),
                version: "1.0",
                lastProbeAt: Date()
            ),
        ]
        let setupURL = tmp.appendingPathComponent("cli_setup.json")
        try! CoreJSON.encode(SetupStore.State(records: cached)).write(to: setupURL)

        let slow = SlowMockCommandRunner(blockSeconds: 30)
        let records = await AllnighterCLI.doctorProbeRecords(
            manifests: manifests,
            labels: ["claude_code": "opus"],
            full: false,
            setupStore: SetupStore(fileURL: setupURL),
            commandRunner: slow
        )

        XCTAssertEqual(records.map(\.driverId), ["claude_code"])
        XCTAssertEqual(slow.runCount, 0, "cached quota-free path must not spawn subprocesses")
    }

    func testDefaultDoctorProbeCompletesWithinBoundWhenCacheEmpty() async {
        let manifests = [
            DriverManifest(
                id: "slow_cli", displayName: "Slow", kind: .headlessCLI,
                detectCommand: "slow_cli --version"
            ),
        ]
        let slow = SlowMockCommandRunner(blockSeconds: 30)
        let setupStore = SetupStore(fileURL: tmp.appendingPathComponent("empty_setup.json"))

        let start = ContinuousClock.now
        let records = await AllnighterCLI.doctorProbeRecords(
            manifests: manifests,
            labels: ["slow_cli": "m"],
            full: false,
            setupStore: setupStore,
            commandRunner: slow
        )
        let elapsed = start.duration(to: .now)

        XCTAssertFalse(records.isEmpty)
        XCTAssertLessThan(elapsed, .seconds(5), "fallback detect-only path must honor hard timeouts")
    }
}

/// Command runner that blocks longer than any doctor default-path timeout.
private final class SlowMockCommandRunner: CommandRunner, @unchecked Sendable {
    private(set) var runCount = 0
    private let blockSeconds: Int

    init(blockSeconds: Int) { self.blockSeconds = blockSeconds }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        runCount += 1
        try? await Task.sleep(for: .seconds(blockSeconds))
        return CommandResult(stdout: "blocked", stderr: "", exitCode: 0)
    }
}
