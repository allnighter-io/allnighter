import XCTest
@testable import AllnighterEngine

/// SC-S02 — `refreshAfterInstall()`: always stages the current executable to
/// the stable binary path; rebinds the LaunchAgent only when a plist is already
/// installed (opt-in stays opt-in). All launchd/file effects injected.
final class ServeInstallRefreshTests: XCTestCase {

    private final class Harness: @unchecked Sendable {
        var bootoutCalls: [String] = []
        var bootstrapCalls: [String] = []
        var stageCalls: [(source: URL, destination: URL)] = []
        var writtenPlists: [(url: URL, plist: ServeLifecycle.AgentPlist)] = []

        var plistPresent = false
        var stageResult: Result<ServeStableBinary.StagingResult, ServeStableBinary.Failure>?
        var bootoutError: Error?
        var bootstrapError: Error?
        var writeError: Error?

        let plistURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).plist")
        let stagedURL = URL(fileURLWithPath: "/tmp/staged-\(UUID().uuidString)/alln")
        let currentExecutableURL = URL(fileURLWithPath: "/Users/dogfood/.local/bin/alln")

        func lifecycle(stagedBinaryURL: URL? = nil) -> ServeLifecycle {
            ServeLifecycle(
                plistURL: plistURL,
                bootout: { [self] label in
                    bootoutCalls.append(label)
                    if let bootoutError { throw bootoutError }
                },
                plistExists: { [self] _ in plistPresent },
                removePlist: { _ in },
                stagedBinaryURL: stagedBinaryURL ?? stagedURL,
                currentExecutableURL: currentExecutableURL,
                stagedBinaryExists: { _ in true },
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

    // MARK: - Stage-only (no plist present)

    func testRefreshStageOnlyWhenPlistAbsent() {
        let h = Harness()
        h.plistPresent = false
        let result = h.lifecycle().refreshAfterInstall()
        XCTAssertEqual(result.outcome, .refreshed)
        XCTAssertTrue(result.staged)
        XCTAssertTrue(result.bytesReplaced)
        XCTAssertFalse(result.rebound)
        XCTAssertEqual(h.stageCalls.count, 1)
        XCTAssertEqual(h.stageCalls[0].source, h.currentExecutableURL)
        XCTAssertEqual(h.stageCalls[0].destination, h.stagedURL)
        XCTAssertTrue(h.bootoutCalls.isEmpty, "no plist — nothing to bootout")
        XCTAssertTrue(h.writtenPlists.isEmpty, "no plist — nothing to write")
        XCTAssertTrue(h.bootstrapCalls.isEmpty, "no plist — nothing to bootstrap")
    }

    // MARK: - Stage + rebind (plist present)

    func testRefreshStagesAndRebindsWhenPlistPresent() {
        let h = Harness()
        h.plistPresent = true
        let result = h.lifecycle().refreshAfterInstall()
        XCTAssertEqual(result.outcome, .refreshedAndRebound)
        XCTAssertTrue(result.staged)
        XCTAssertTrue(result.bytesReplaced)
        XCTAssertTrue(result.rebound)
        XCTAssertEqual(h.stageCalls.count, 1)
        XCTAssertEqual(h.bootoutCalls, [ServeLaunchAgentStatus.label])
        XCTAssertEqual(h.writtenPlists.count, 1)
        let plist = h.writtenPlists[0].plist
        XCTAssertEqual(plist.programArguments, [h.stagedURL.path, "serve"])
        XCTAssertTrue(plist.keepAlive)
        XCTAssertTrue(plist.runAtLoad)
        XCTAssertEqual(h.bootstrapCalls, [h.plistURL.path])
    }

    /// Always stages — even when a prior copy already exists — unlike enable()
    /// which skips staging when the binary is already present.
    func testRefreshAlwaysStagesEvenWhenStagedBinaryExists() {
        let h = Harness()
        h.plistPresent = false
        _ = h.lifecycle().refreshAfterInstall()
        XCTAssertEqual(h.stageCalls.count, 1, "always stages — identity byte refresh on every install")
    }

    // MARK: - Refuse /.local/bin/

    func testRefreshRefusesLocalBin() {
        let h = Harness()
        let refused = URL(fileURLWithPath: "/Users/dogfood/.local/bin/alln")
        let result = h.lifecycle(stagedBinaryURL: refused).refreshAfterInstall()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertFalse(result.staged)
        XCTAssertFalse(result.rebound)
        XCTAssertTrue(h.stageCalls.isEmpty)
        XCTAssertTrue(h.bootoutCalls.isEmpty)
    }

    // MARK: - Stage failure

    func testRefreshStageFailureReadsFailed() {
        let h = Harness()
        h.stageResult = .failure(.sourceNotReadable(h.currentExecutableURL))
        let result = h.lifecycle().refreshAfterInstall()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertFalse(result.staged)
        XCTAssertFalse(result.rebound)
        XCTAssertEqual(h.stageCalls.count, 1)
        XCTAssertTrue(h.bootoutCalls.isEmpty)
        XCTAssertTrue(h.writtenPlists.isEmpty)
    }

    // MARK: - Bootout failure (plist present, rebind path)

    func testRefreshBootoutFailureReadsFailedAfterStage() {
        let h = Harness()
        h.plistPresent = true
        h.bootoutError = ServeLifecycle.BootoutError(terminationStatus: 1, message: "Boot-out failed: 5: Input/output error")
        let result = h.lifecycle().refreshAfterInstall()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.staged, "staging succeeded before bootout failed")
        XCTAssertFalse(result.rebound)
        XCTAssertEqual(h.stageCalls.count, 1)
        XCTAssertEqual(h.bootoutCalls.count, 1)
        XCTAssertTrue(h.writtenPlists.isEmpty, "plist not written after bootout failure")
        XCTAssertTrue(h.bootstrapCalls.isEmpty)
    }

    // MARK: - Bootstrap failure (plist present, rebind path)

    func testRefreshBootstrapFailureReadsFailedAfterStage() {
        let h = Harness()
        h.plistPresent = true
        h.bootstrapError = ServeLifecycle.BootstrapError(terminationStatus: 1, message: "Bootstrap failed: 5: Input/output error")
        let result = h.lifecycle().refreshAfterInstall()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.staged)
        XCTAssertFalse(result.rebound)
        XCTAssertEqual(h.stageCalls.count, 1)
        XCTAssertTrue(result.staged)
        XCTAssertEqual(h.writtenPlists.count, 1, "plist was written before bootstrap failed")
    }

    // MARK: - Codable round-trip

    func testRefreshResultCodableRoundTrip() throws {
        let h = Harness()
        h.plistPresent = true
        let result = h.lifecycle().refreshAfterInstall()
        let decoded = try JSONDecoder().decode(ServeLifecycle.RefreshResult.self,
                                                from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded, result)
    }

    func testRefreshResultStageOnlyCodableRoundTrip() throws {
        let h = Harness()
        h.plistPresent = false
        let result = h.lifecycle().refreshAfterInstall()
        let decoded = try JSONDecoder().decode(ServeLifecycle.RefreshResult.self,
                                                from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded, result)
    }
}
