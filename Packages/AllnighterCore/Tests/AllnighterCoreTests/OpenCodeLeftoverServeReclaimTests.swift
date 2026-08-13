import XCTest
@testable import AllnighterCore

/// Fixtures only — never lsof, never live Ollama, never a real serve.
final class OpenCodeLeftoverServeReclaimTests: XCTestCase {
    func testDecideRefusesAllnServeBeforeOpenCode() {
        XCTAssertEqual(
            OpenCodeLeftoverServeReclaim.decide(commandLine: "alln serve"),
            .refuseAllnServe
        )
        XCTAssertEqual(
            OpenCodeLeftoverServeReclaim.decide(
                commandLine: "/Users/mike/.local/bin/alln serve --health --json"
            ),
            .refuseAllnServe
        )
        XCTAssertEqual(
            OpenCodeLeftoverServeReclaim.decide(commandLine: "COMMAND\nalln serve"),
            .refuseAllnServe
        )
    }

    func testDecideReclaimsLeftoverOpenCodeServe() {
        XCTAssertEqual(
            OpenCodeLeftoverServeReclaim.decide(
                commandLine: "opencode serve --port 4096"
            ),
            .reclaimOpenCodeServe
        )
        XCTAssertEqual(
            OpenCodeLeftoverServeReclaim.decide(
                commandLine: "/opt/homebrew/bin/opencode serve --port 4096"
            ),
            .reclaimOpenCodeServe
        )
    }

    func testDecideSkipsAttachClientAndForeignListeners() {
        XCTAssertEqual(
            OpenCodeLeftoverServeReclaim.decide(
                commandLine: "opencode run --attach http://127.0.0.1:4096"
            ),
            .skipForeign
        )
        XCTAssertEqual(
            OpenCodeLeftoverServeReclaim.decide(commandLine: "node server.js"),
            .skipForeign
        )
        XCTAssertEqual(OpenCodeLeftoverServeReclaim.decide(commandLine: nil), .skipUnreadableCommand)
        XCTAssertEqual(OpenCodeLeftoverServeReclaim.decide(commandLine: "   \n"), .skipUnreadableCommand)
    }

    func testReclaimTerminatesOnlyLeftoverOpenCodeServe() {
        let table = RecordingTable(
            pid: 14749,
            command: "/opt/homebrew/bin/opencode serve --port 4096"
        )
        let outcome = OpenCodeLeftoverServeReclaim.reclaim(port: 4096, table: table.table)
        XCTAssertEqual(outcome, .reclaimed(pid: 14749, command: table.command))
        XCTAssertEqual(table.terminated, [14749])
    }

    func testReclaimRefusesAllnServeWithoutTerminate() {
        let table = RecordingTable(
            pid: 43273,
            command: "alln serve"
        )
        let outcome = OpenCodeLeftoverServeReclaim.reclaim(port: 4096, table: table.table)
        XCTAssertEqual(outcome, .refusedAllnServe(pid: 43273, command: "alln serve"))
        XCTAssertTrue(table.terminated.isEmpty)
    }

    func testReclaimIdleWhenNothingListens() {
        let table = RecordingTable(pid: nil, command: "opencode serve --port 4096")
        XCTAssertEqual(OpenCodeLeftoverServeReclaim.reclaim(table: table.table), .idle)
        XCTAssertTrue(table.terminated.isEmpty)
        XCTAssertTrue(table.commandLookups.isEmpty)
    }

    func testResolvedTableUnderTestHostIsInactiveWithoutOverride() {
        let table = OpenCodeLeftoverServeReclaim.resolvedTable(override: nil, isTestHost: true)
        XCTAssertEqual(OpenCodeLeftoverServeReclaim.reclaim(table: table), .idle)
        XCTAssertTrue(AllnighterSupportRoot.isRunningUnderTestHost)
    }

    func testStaleModelNotFoundReasonIsSpecific() {
        XCTAssertTrue(
            OpenCodeLeftoverServeReclaim.isStaleModelNotFoundReason(
                "opencode session error: Model not found: ollama/gpt-oss:20b"
            )
        )
        XCTAssertFalse(
            OpenCodeLeftoverServeReclaim.isStaleModelNotFoundReason(
                "opencode session error: Unexpected server error"
            )
        )
        XCTAssertFalse(
            OpenCodeLeftoverServeReclaim.isStaleModelNotFoundReason("Model not found: ollama/x")
        )
        XCTAssertFalse(OpenCodeLeftoverServeReclaim.isStaleModelNotFoundReason(nil))
    }

    func testSetupWriteRecyclesLeftoverOpenCodeServe() throws {
        let dir = try scratchDir()
        let config = dir.appendingPathComponent("opencode.json")
        let receipt = dir.appendingPathComponent("receipt.json")
        try Data(#"{ "enabled_providers": ["opencode-go"] }"#.utf8).write(to: config)
        let table = RecordingTable(
            pid: 99,
            command: "opencode serve --port 4096"
        )
        let report = try OpenCodeOllamaSetup.apply(
            configURL: config,
            receiptURL: receipt,
            now: Date(timeIntervalSince1970: 1_754_000_000),
            dryRun: false,
            isTestHost: true,
            serveReclaim: table.table
        )
        XCTAssertTrue(report.wrote)
        XCTAssertEqual(report.leftoverServeAction, "reclaimed")
        XCTAssertEqual(report.leftoverServePID, 99)
        XCTAssertEqual(table.terminated, [99])
        XCTAssertTrue(report.message.contains("recycled leftover opencode serve"))
    }

    func testSetupDoesNotReclaimOnDryRunOrAlreadyWired() throws {
        let dir = try scratchDir()
        let config = dir.appendingPathComponent("opencode.json")
        let receipt = dir.appendingPathComponent("receipt.json")
        try Data(#"{ "enabled_providers": ["opencode-go"] }"#.utf8).write(to: config)
        let table = RecordingTable(pid: 99, command: "opencode serve --port 4096")

        let dry = try OpenCodeOllamaSetup.apply(
            configURL: config,
            receiptURL: receipt,
            now: Date(timeIntervalSince1970: 1_754_000_000),
            dryRun: true,
            isTestHost: true,
            serveReclaim: table.table
        )
        XCTAssertFalse(dry.wrote)
        XCTAssertNil(dry.leftoverServeAction)
        XCTAssertTrue(table.terminated.isEmpty)

        let first = try OpenCodeOllamaSetup.apply(
            configURL: config,
            receiptURL: receipt,
            now: Date(timeIntervalSince1970: 1_754_000_000),
            dryRun: false,
            isTestHost: true,
            serveReclaim: table.table
        )
        XCTAssertTrue(first.wrote)
        XCTAssertEqual(table.terminated, [99])

        let second = try OpenCodeOllamaSetup.apply(
            configURL: config,
            receiptURL: receipt,
            now: Date(timeIntervalSince1970: 1_754_000_060),
            dryRun: false,
            isTestHost: true,
            serveReclaim: table.table
        )
        XCTAssertFalse(second.wrote)
        XCTAssertTrue(second.alreadyWired)
        XCTAssertNil(second.leftoverServeAction)
        XCTAssertEqual(table.terminated, [99])
    }

    func testSetupWriteRefusesAllnServe() throws {
        let dir = try scratchDir()
        let config = dir.appendingPathComponent("opencode.json")
        let receipt = dir.appendingPathComponent("receipt.json")
        try Data(#"{}"#.utf8).write(to: config)
        let table = RecordingTable(pid: 43273, command: "alln serve")
        let report = try OpenCodeOllamaSetup.apply(
            configURL: config,
            receiptURL: receipt,
            now: Date(timeIntervalSince1970: 1_754_000_000),
            dryRun: false,
            isTestHost: true,
            serveReclaim: table.table
        )
        XCTAssertTrue(report.wrote)
        XCTAssertEqual(report.leftoverServeAction, "refused_alln_serve")
        XCTAssertTrue(table.terminated.isEmpty)
        XCTAssertTrue(report.message.contains("alln serve"))
        XCTAssertTrue(report.message.contains("not stopping"))
    }

    func testRefreshRetriesOnceAfterReclaimThenSucceeds() async {
        let inner = SequentialInvoker(scripts: [
            .failing(
                "opencode session error: Model not found: ollama/gpt-oss:20b",
                errorKind: .nonzeroExit
            ),
            .answering(["ok"]),
        ])
        let table = RecordingTable(pid: 7, command: "opencode serve --port 4096")
        let runner = OpenCodeStaleModelServeRefreshingWorkerRunner(
            inner: inner,
            table: table.table
        )
        let result = await runner.collect(opencodeInvocation())
        XCTAssertEqual(result.status, .done)
        XCTAssertEqual(result.output, "ok")
        XCTAssertEqual(inner.invokeCount, 2)
        XCTAssertEqual(table.terminated, [7])
    }

    func testRefreshDoesNotLoopWhenModelIsGenuinelyAbsent() async {
        let reason = "opencode session error: Model not found: ollama/missing:1b"
        let inner = SequentialInvoker(scripts: [
            .failing(reason),
            .failing(reason),
            .failing("should not run a third time"),
        ])
        let table = RecordingTable(pid: 7, command: "opencode serve --port 4096")
        let runner = OpenCodeStaleModelServeRefreshingWorkerRunner(
            inner: inner,
            table: table.table
        )
        let result = await runner.collect(opencodeInvocation())
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.errorReason, reason)
        XCTAssertEqual(inner.invokeCount, 2)
        XCTAssertEqual(table.terminated, [7])
    }

    func testRefreshDoesNotRetryWhenListenerIsAllnServe() async {
        let reason = "opencode session error: Model not found: ollama/gpt-oss:20b"
        let inner = SequentialInvoker(scripts: [.failing(reason), .answering(["should not run"])])
        let table = RecordingTable(pid: 43273, command: "alln serve")
        let runner = OpenCodeStaleModelServeRefreshingWorkerRunner(
            inner: inner,
            table: table.table
        )
        let result = await runner.collect(opencodeInvocation())
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.errorReason, reason)
        XCTAssertEqual(inner.invokeCount, 1)
        XCTAssertTrue(table.terminated.isEmpty)
    }

    func testRefreshIgnoresOtherSessionErrorsAndOtherDrivers() async {
        let other = SequentialInvoker(scripts: [
            .failing("opencode session error: Unexpected server error"),
        ])
        let table = RecordingTable(pid: 7, command: "opencode serve --port 4096")
        let opencodeRunner = OpenCodeStaleModelServeRefreshingWorkerRunner(
            inner: other,
            table: table.table
        )
        let otherResult = await opencodeRunner.collect(opencodeInvocation())
        XCTAssertEqual(otherResult.errorReason, "opencode session error: Unexpected server error")
        XCTAssertEqual(other.invokeCount, 1)
        XCTAssertTrue(table.terminated.isEmpty)

        let passthrough = SequentialInvoker(scripts: [.failing(
            "opencode session error: Model not found: ollama/x"
        )])
        let otherDriver = OpenCodeStaleModelServeRefreshingWorkerRunner(
            inner: passthrough,
            table: table.table
        )
        let claude = WorkerInvocation(
            model: Model(
                id: "c", displayName: "c", modelLabel: "opus",
                driverId: "claude_code", role: .both
            ),
            manifest: DriverManifest(
                id: "claude_code",
                displayName: "claude_code",
                kind: .headlessCLI,
                invoke: .init(command: "claude", args: [])
            ),
            prompt: "hi"
        )
        _ = await otherDriver.collect(claude)
        XCTAssertEqual(passthrough.invokeCount, 1)
        XCTAssertTrue(table.terminated.isEmpty)
    }

    // MARK: - Helpers

    private func opencodeInvocation() -> WorkerInvocation {
        WorkerInvocation(
            model: Model(
                id: "local", displayName: "local",
                modelLabel: "ollama/gpt-oss:20b",
                driverId: "opencode", role: .both
            ),
            manifest: DriverManifest(
                id: "opencode",
                displayName: "opencode",
                kind: .headlessCLI,
                invoke: .init(command: "opencode", args: [])
            ),
            prompt: "hi"
        )
    }

    private func scratchDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocl-reclaim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private final class RecordingTable: @unchecked Sendable {
    let pid: Int32?
    let command: String
    private let lock = NSLock()
    private(set) var terminated: [Int32] = []
    private(set) var commandLookups: [Int32] = []

    init(pid: Int32?, command: String) {
        self.pid = pid
        self.command = command
    }

    var table: OpenCodeLeftoverServeReclaim.Table {
        OpenCodeLeftoverServeReclaim.Table(
            listenerPID: { [pid] _ in pid },
            commandLine: { [weak self] lookedUp in
                self?.lock.lock()
                self?.commandLookups.append(lookedUp)
                self?.lock.unlock()
                return self?.command
            },
            terminate: { [weak self] victim in
                self?.lock.lock()
                self?.terminated.append(victim)
                self?.lock.unlock()
            }
        )
    }
}

private final class SequentialInvoker: WorkerInvoking, @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [MockWorkerInvoking]
    private(set) var invokeCount = 0

    init(scripts: [MockWorkerInvoking]) {
        remaining = scripts
    }

    func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        lock.lock()
        invokeCount += 1
        let next: MockWorkerInvoking
        if remaining.isEmpty {
            next = .failing("sequential invoker exhausted")
        } else {
            next = remaining.removeFirst()
        }
        lock.unlock()
        return next.invoke(invocation)
    }
}
