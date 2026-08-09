import XCTest
@testable import AllnighterEngine

/// SC-S04b — product-owned serve enable/disable against the staged stable
/// binary. All launchd/file effects injected; no live `launchctl bootout` or
/// `bootstrap` and no real plist write ever runs against the host.
final class ServeLifecycleEnableTests: XCTestCase {

    /// Records bootout/bootstrap/stage/plist-write attempts; failures
    /// injectable.
    private final class Harness: @unchecked Sendable {
        var bootoutCalls: [String] = []
        var bootstrapCalls: [String] = []
        var stageCalls: [(source: URL, destination: URL)] = []
        var writtenPlists: [(url: URL, plist: ServeLifecycle.AgentPlist)] = []
        var deletedURLs: [URL] = []

        var stagedExists = true
        var plistPresent = false
        var stageResult: Result<ServeStableBinary.StagingResult, ServeStableBinary.Failure>?
        var bootoutError: Error?
        var bootstrapError: Error?
        var writeError: Error?
        var deleteError: Error?

        let plistURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).plist")
        let stagedURL = URL(fileURLWithPath: "/tmp/staged-\(UUID().uuidString)/alln")
        /// The dogfood shape: the running CLI is the adhoc debug symlink.
        let currentExecutableURL = URL(fileURLWithPath: "/Users/dogfood/.local/bin/alln")

        func lifecycle(stagedBinaryURL: URL? = nil) -> ServeLifecycle {
            ServeLifecycle(
                plistURL: plistURL,
                bootout: { [self] label in
                    bootoutCalls.append(label)
                    if let bootoutError { throw bootoutError }
                },
                plistExists: { [self] _ in plistPresent },
                removePlist: { [self] url in
                    if let deleteError { throw deleteError }
                    deletedURLs.append(url)
                },
                stagedBinaryURL: stagedBinaryURL ?? stagedURL,
                currentExecutableURL: currentExecutableURL,
                stagedBinaryExists: { [self] _ in stagedExists },
                stage: { [self] source, destination in
                    stageCalls.append((source, destination))
                    return stageResult ?? .success(.init(url: destination, bytesWereReplaced: true))
                },
                writePlist: { [self] url, plist in
                    if let writeError { throw writeError }
                    writtenPlists.append((url, plist))
                },
                bootstrap: { [self] path in
                    bootstrapCalls.append(path)
                    if let bootstrapError { throw bootstrapError }
                }
            )
        }
    }

    // MARK: - enable()

    /// Staged binary already present: no staging, plist written aimed at the
    /// staged binary with KeepAlive/RunAtLoad, prior registration booted out,
    /// agent bootstrapped.
    func testEnableWithStagedBinaryWritesPlistAndBootstraps() {
        let h = Harness()
        let result = h.lifecycle().enable()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertTrue(h.stageCalls.isEmpty, "staged binary present — no staging")
        XCTAssertEqual(h.bootoutCalls, [ServeLaunchAgentStatus.label])
        XCTAssertEqual(h.bootstrapCalls, [h.plistURL.path])
        XCTAssertEqual(h.writtenPlists.count, 1)
        let plist = h.writtenPlists[0].plist
        XCTAssertEqual(plist.label, ServeLaunchAgentStatus.label)
        XCTAssertEqual(plist.programArguments, [h.stagedURL.path, "serve"])
        XCTAssertTrue(plist.keepAlive)
        XCTAssertTrue(plist.runAtLoad)
        XCTAssertTrue(result.plistWritten)
        XCTAssertTrue(result.bootstrapped)
    }

    /// No staged copy yet: enable stages from the running executable first,
    /// then points the agent at the staged destination.
    func testEnableStagesFromCurrentExecutableWhenMissing() {
        let h = Harness()
        h.stagedExists = false
        let result = h.lifecycle().enable()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertEqual(h.stageCalls.count, 1)
        XCTAssertEqual(h.stageCalls[0].source, h.currentExecutableURL)
        XCTAssertEqual(h.stageCalls[0].destination, h.stagedURL)
        XCTAssertEqual(h.writtenPlists[0].plist.programArguments, [h.stagedURL.path, "serve"])
        XCTAssertTrue(result.stagedBytesReplaced)
    }

    /// Even when the running CLI is the `~/.local/bin` debug symlink, the
    /// agent's ProgramArguments never name that path.
    func testEnableNeverUsesDebugSymlinkPath() {
        let h = Harness()
        h.stagedExists = false
        let result = h.lifecycle().enable()
        XCTAssertEqual(result.outcome, .enabled)
        let program = h.writtenPlists[0].plist.programArguments[0]
        XCTAssertFalse(program.contains(".local/bin"), "agent must not supervise the debug symlink")
        XCTAssertEqual(program, h.stagedURL.path)
    }

    /// A staged destination under `~/.local/bin` is refused outright — that
    /// identity is exactly the CODE_RED landmine.
    func testEnableRefusesStagedDestinationUnderLocalBin() {
        let h = Harness()
        let refused = URL(fileURLWithPath: "/Users/dogfood/.local/bin/alln")
        let result = h.lifecycle(stagedBinaryURL: refused).enable()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(h.stageCalls.isEmpty)
        XCTAssertTrue(h.writtenPlists.isEmpty)
        XCTAssertTrue(h.bootoutCalls.isEmpty)
        XCTAssertTrue(h.bootstrapCalls.isEmpty)
    }

    /// A staging failure is never painted as enabled; nothing is written or
    /// bootstrapped.
    func testEnableStageFailureReadsFailed() {
        let h = Harness()
        h.stagedExists = false
        h.stageResult = .failure(.sourceNotReadable(h.currentExecutableURL))
        let result = h.lifecycle().enable()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(h.writtenPlists.isEmpty)
        XCTAssertTrue(h.bootstrapCalls.isEmpty)
    }

    /// A real bootout failure (not not-loaded) stops enable before the plist
    /// is written — never half-register over a live prior registration.
    func testEnableBootoutFailureReadsFailed() {
        let h = Harness()
        h.bootoutError = ServeLifecycle.BootoutError(terminationStatus: 1, message: "Boot-out failed: 5: Input/output error")
        let result = h.lifecycle().enable()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(h.writtenPlists.isEmpty)
        XCTAssertTrue(h.bootstrapCalls.isEmpty)
    }

    /// A bootstrap refusal reads failed even though the plist landed.
    func testEnableBootstrapFailureReadsFailed() {
        let h = Harness()
        h.bootstrapError = ServeLifecycle.BootstrapError(terminationStatus: 1, message: "Bootstrap failed: 5: Input/output error")
        let result = h.lifecycle().enable()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.plistWritten)
        XCTAssertFalse(result.bootstrapped)
    }

    /// The enable result round-trips through JSON — it is the
    /// `serve enable --json` wire shape.
    func testEnableResultCodableRoundTrip() throws {
        let h = Harness()
        let result = h.lifecycle().enable()
        let decoded = try JSONDecoder().decode(ServeLifecycle.EnableResult.self,
                                               from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded, result)
    }

    /// The written plist encodes the launchd keys launchd expects.
    func testAgentPlistEncodesLaunchdKeys() throws {
        let plist = ServeLifecycle.AgentPlist(label: ServeLaunchAgentStatus.label,
                                              programArguments: ["/x/alln", "serve"],
                                              keepAlive: true, runAtLoad: true)
        let data = try PropertyListEncoder().encode(plist)
        let decoded = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual(decoded?["Label"] as? String, ServeLaunchAgentStatus.label)
        XCTAssertEqual(decoded?["ProgramArguments"] as? [String], ["/x/alln", "serve"])
        XCTAssertEqual(decoded?["KeepAlive"] as? Bool, true)
        XCTAssertEqual(decoded?["RunAtLoad"] as? Bool, true)
    }

    // MARK: - disable()

    /// Disable is plain removal: bootout + plist delete, no orphan left.
    func testDisableBootsOutAndDeletesPlist() {
        let h = Harness()
        h.plistPresent = true
        let result = h.lifecycle().disable()
        XCTAssertEqual(result.outcome, .removed)
        XCTAssertEqual(h.bootoutCalls, [ServeLaunchAgentStatus.label])
        XCTAssertEqual(h.deletedURLs, [h.plistURL])
    }

    /// Nothing installed: disable is a no-op success.
    func testDisableAbsentIsNoOp() {
        let h = Harness()
        h.plistPresent = false
        let result = h.lifecycle().disable()
        XCTAssertEqual(result.outcome, .removed)
        XCTAssertFalse(result.plistDeleted)
        XCTAssertTrue(h.deletedURLs.isEmpty)
    }
}
