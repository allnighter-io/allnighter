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

    func testDefaultDoctorProbeKillsAndReapsHungVersionProcess() async throws {
        let executable = tmp.appendingPathComponent("hung_probe")
        let pidFile = tmp.appendingPathComponent("hung_probe.pid")
        try """
        #!/bin/sh
        printf '%s' "$$" > "\(pidFile.path)"
        trap '' TERM
        while true; do sleep 1; done
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let manifests = [
            DriverManifest(
                id: "hung_probe", displayName: "Hung Probe", kind: .headlessCLI,
                detectCommand: "hung_probe --version",
                invoke: .init(command: "hung_probe", args: ["{{prompt}}"]),
                setup: SetupBlock(bins: ["hung_probe"], knownPaths: [tmp.path])
            ),
        ]
        let setupStore = SetupStore(fileURL: tmp.appendingPathComponent("empty_setup.json"))

        let start = ContinuousClock.now
        let records = await AllnighterCLI.doctorProbeRecords(
            manifests: manifests,
            labels: ["hung_probe": "m"],
            full: false,
            setupStore: setupStore
        )
        let elapsed = start.duration(to: .now)

        XCTAssertEqual(records.first?.status.kind, .probeFailed)
        XCTAssertLessThan(elapsed, .seconds(5), "fallback detect-only path must honor hard timeouts")

        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
        let pid = try XCTUnwrap(Int32(pidText))
        XCTAssertFalse(
            ProcessOwnership.processAlive(pid),
            "doctor must reap a probe that ignores SIGTERM"
        )
    }

    func testFullDoctorPersistsFreshReadinessForLaterPanelResolution() async throws {
        let setupURL = tmp.appendingPathComponent("full_setup.json")
        let setupStore = SetupStore(fileURL: setupURL)
        try setupStore.save(.init(records: [
            ToolProbeRecord(
                driverId: "unrelated",
                status: .ready(version: "1"),
                lastProbeAt: .distantPast
            ),
        ]))
        let manifests = [
            DriverManifest(
                id: "codex", displayName: "Codex", kind: .headlessCLI,
                detectCommand: "codex --version",
                invoke: .init(command: "codex", args: ["exec", "{{prompt}}"]),
                setup: SetupBlock(bins: ["codex"], knownPaths: [])
            ),
        ]

        let records = await AllnighterCLI.doctorProbeRecords(
            manifests: manifests,
            labels: ["codex": "gpt-5.6-sol"],
            full: true,
            setupStore: setupStore,
            commandRunner: MockCommandRunner(
                scripts: [:],
                fallback: .init(stdout: "", exitCode: 1)
            )
        )

        XCTAssertEqual(records.map(\.driverId), ["codex"])
        XCTAssertEqual(
            Set(setupStore.load().records.map(\.driverId)),
            Set(["codex", "unrelated"]),
            "full doctor must refresh its drivers without erasing other cached sources"
        )
        XCTAssertEqual(
            setupStore.load().records.first { $0.driverId == "codex" }?.status,
            records.first?.status
        )
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
