import XCTest
@testable import AllnighterEngine

/// ASR-S02c — convergent supervisor transaction: enable, disable, restart, repair
/// all converge through one routine. Every launchd/file effect injected; no live
/// `launchctl` and no real plist write ever runs against the host.
final class ServeLifecycleEnableTests: XCTestCase {

    private final class Harness: @unchecked Sendable {
        var bootoutCalls: [String] = []
        var bootstrapCalls: [String] = []
        var writtenPlists: [(url: URL, plist: ServeLifecycle.AgentPlist)] = []
        var deletedURLs: [URL] = []
        var desiredWrites: [(state: ServeDesiredState.State, home: URL)] = []
        var stagedBytesDeletedURLs: [URL] = []

        var bootoutError: Error?
        var bootstrapError: Error?
        var writeError: Error?
        var deleteError: Error?

        var desiredWriteResult: Result<Void, ServeDesiredState.Failure> = .success(())
        var injectedReading: ServeDesiredState.Reading = .absent
        var canonicalExists = true
        var jobIsLoaded = false
        var recordedSleeps: [TimeInterval] = []
        var clockTime: Date
        var clockAdvance: TimeInterval = 0
        var injectedPlistProgramArgument: String?
        var stagedBytesPresent = false
        var stagedRemoveError: Error?

        let plistURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).plist")
        let homeURL = URL(fileURLWithPath: "/tmp/home-\(UUID().uuidString)")
        let canonicalURL: URL
        let stagedBinaryURL: URL

        init(canonicalBase: String = "/tmp/canonical-\(UUID().uuidString)") {
            let dir = URL(fileURLWithPath: canonicalBase)
            canonicalURL = dir.appendingPathComponent("alln")
            stagedBinaryURL = URL(fileURLWithPath: "/tmp/staged-\(UUID().uuidString)/alln")
            clockTime = Date(timeIntervalSince1970: 1_000_000)
        }

        var lifecycle: ServeLifecycle {
            ServeLifecycle(
                plistURL: plistURL,
                bootout: { [self] label in
                    bootoutCalls.append(label)
                    if let bootoutError { throw bootoutError }
                },
                plistExists: { [self] _ in !deletedURLs.contains(plistURL) && FileManager.default.fileExists(atPath: plistURL.path) },
                removePlist: { [self] url in
                    if let deleteError { throw deleteError }
                    deletedURLs.append(url)
                },
                writePlist: { [self] url, plist in
                    if let writeError { throw writeError }
                    writtenPlists.append((url, plist))
                },
                bootstrap: { [self] path in
                    bootstrapCalls.append(path)
                    if let bootstrapError { throw bootstrapError }
                },
                homeDirectory: homeURL,
                canonicalBinaryURL: canonicalURL,
                canonicalBinaryExists: { [self] _ in canonicalExists },
                readDesiredState: { [self] _ in injectedReading },
                writeDesiredState: { [self] state, home in
                    desiredWrites.append((state, home))
                    return desiredWriteResult
                },
                verifyJobLoaded: { [self] _ in jobIsLoaded },
                sleep: { [self] d in
                    recordedSleeps.append(d)
                    clockTime = clockTime.addingTimeInterval(d)
                },
                clock: { [self] in clockTime },
                stagedBinaryURL: stagedBinaryURL,
                readExistingPlistProgramArgument: { [self] _ in injectedPlistProgramArgument },
                stagedBytesExist: { [self] _ in stagedBytesPresent },
                removeStagedBytes: { [self] url in
                    if let stagedRemoveError { throw stagedRemoveError }
                    stagedBytesDeletedURLs.append(url)
                }
            )
        }

        func advanceClockBeyond(_ seconds: TimeInterval) {
            clockAdvance = seconds
            clockTime = clockTime.addingTimeInterval(seconds)
        }

        func createPlistFile() {
            try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("old-plist".utf8).write(to: plistURL, options: .atomic)
        }
    }

    // MARK: - canonical binary path

    func testProgramArgumentsPointsAtCanonicalBinary() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertEqual(h.writtenPlists.count, 1)
        XCTAssertEqual(h.writtenPlists[0].plist.programArguments, [h.canonicalURL.path, "serve"])
        XCTAssertEqual(result.canonicalBinaryPath, h.canonicalURL.path)
    }

    func testProgramArgumentsNeverPointsAtStagedPath() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .enabled)
        let program = h.writtenPlists[0].plist.programArguments[0]
        XCTAssertEqual(program, h.canonicalURL.path)
        XCTAssertFalse(program.contains("Application Support"), "ProgramArguments must be canonical, not staged")
    }

    // MARK: - enable writes desired state then converges

    func testEnableWritesDesiredEnabledThenConverges() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertEqual(h.desiredWrites.count, 1)
        XCTAssertEqual(h.desiredWrites[0].state, .enabled)
        XCTAssertEqual(h.desiredWrites[0].home, h.homeURL)
        XCTAssertTrue(result.plistWritten)
        XCTAssertTrue(result.bootstrapped)
    }

    func testEnableWritesNoPlistWhenMissingCanonicalBinary() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.canonicalExists = false
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .missingCanonicalBinary)
        XCTAssertTrue(h.writtenPlists.isEmpty, "no plist when canonical binary is missing")
        XCTAssertTrue(h.bootstrapCalls.isEmpty, "no bootstrap when canonical binary is missing")
        XCTAssertTrue(result.detail.contains("SERVE_INSTALL_FAILED"), "detail must name SERVE_INSTALL_FAILED: \(result.detail)")
        XCTAssertTrue(result.detail.contains(h.canonicalURL.path), "detail must name the missing path")
        XCTAssertTrue(result.detail.contains("install-cli"), "detail must name the recovery command")
    }

    func testEnableWithMissingCanonicalBinaryCreatesNoBinary() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.canonicalExists = false
        _ = await h.lifecycle.enable()
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.canonicalURL.path), "must not create the canonical binary")
    }

    // MARK: - unreadable desired state → degraded

    func testUnreadableDesiredStateNoBootoutNoBootstrap() async {
        let h = Harness()
        h.injectedReading = .unreadable(reason: "corrupt JSON")
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertEqual(result.desiredStateReading, "unreadable")
        XCTAssertTrue(h.bootoutCalls.isEmpty, "no bootout on unreadable")
        XCTAssertTrue(h.bootstrapCalls.isEmpty, "no bootstrap on unreadable")
        XCTAssertTrue(h.writtenPlists.isEmpty, "no plist on unreadable")
    }

    func testRepairUnreadableReturnsDegraded() async {
        let h = Harness()
        h.injectedReading = .unreadable(reason: "truncated")
        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertTrue(h.bootoutCalls.isEmpty)
        XCTAssertTrue(h.bootstrapCalls.isEmpty)
    }

    // MARK: - disabled desired state

    func testExplicitDisabledNoBootstrap() async {
        let h = Harness()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .disabled)
        XCTAssertTrue(h.bootstrapCalls.isEmpty, "no bootstrap when desired state is disabled")
        XCTAssertTrue(h.writtenPlists.isEmpty, "no plist when desired state is disabled")
    }

    func testDisableWritesDesiredDisabledThenConverges() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        let result = await h.lifecycle.disable()
        XCTAssertEqual(result.outcome, .disabled)
        XCTAssertEqual(h.desiredWrites.count, 1)
        XCTAssertEqual(h.desiredWrites[0].state, .disabled)
        XCTAssertTrue(h.bootoutCalls.contains(ServeLifecycle.label))
        XCTAssertTrue(h.deletedURLs.contains(h.plistURL))
    }

    func testDisableBootoutPrecedesPlistRemoval() async {
        final class Ordering: @unchecked Sendable {
            var events: [String] = []
        }
        let ordering = Ordering()
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())

        let lifecycle = ServeLifecycle(
            plistURL: h.plistURL,
            bootout: { _ in ordering.events.append("bootout"); h.bootoutCalls.append("label") },
            plistExists: { _ in !h.deletedURLs.contains(h.plistURL) },
            removePlist: { url in ordering.events.append("delete"); h.deletedURLs.append(url) },
            writePlist: { _, _ in },
            bootstrap: { _ in },
            homeDirectory: h.homeURL,
            canonicalBinaryURL: h.canonicalURL,
            canonicalBinaryExists: { _ in true },
            readDesiredState: { _ in .present(state: .disabled, updatedAt: Date()) },
            writeDesiredState: { _, _ in .success(()) },
            verifyJobLoaded: { _ in false },
            sleep: { _ in },
            clock: { h.clockTime }
        )

        _ = await lifecycle.disable()
        XCTAssertEqual(ordering.events.first, "bootout", "bootout must happen before plist delete, got: \(ordering.events)")
        XCTAssertTrue(ordering.events.contains("bootout"))
        XCTAssertTrue(ordering.events.contains("delete"))
        guard let bootIdx = ordering.events.firstIndex(of: "bootout"),
              let deleteIdx = ordering.events.firstIndex(of: "delete") else {
            XCTFail("missing events"); return
        }
        XCTAssertLessThan(bootIdx, deleteIdx, "bootout must precede plist delete")
    }

    // MARK: - absent → treated as enabled (migration)

    func testAbsentDesiredStateConvergesToEnabled() async {
        let h = Harness()
        h.injectedReading = .absent
        h.jobIsLoaded = true
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertTrue(h.writtenPlists.count >= 1)
        XCTAssertTrue(h.bootstrapCalls.count >= 1)
        XCTAssertEqual(result.desiredStateReading, "absent")
    }

    // MARK: - restart

    func testRestartNoDesiredStateWrite() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        let result = await h.lifecycle.restart()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertTrue(h.desiredWrites.isEmpty, "restart must not write desired state")
        XCTAssertTrue(h.bootoutCalls.contains(ServeLifecycle.label))
        XCTAssertTrue(h.bootstrapCalls.contains(h.plistURL.path))
    }

    func testRestartRefusesWhenDesiredDisabled() async {
        let h = Harness()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        let result = await h.lifecycle.restart()
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertTrue(h.bootoutCalls.isEmpty)
        XCTAssertTrue(h.bootstrapCalls.isEmpty)
    }

    func testRestartRefusesWhenUnreadable() async {
        let h = Harness()
        h.injectedReading = .unreadable(reason: "corrupt")
        let result = await h.lifecycle.restart()
        XCTAssertEqual(result.outcome, .degraded)
    }

    // MARK: - repair reinstalls

    func testRepairOnEnabledReinstalls() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertTrue(h.writtenPlists.count >= 1, "repair must write plist")
        XCTAssertTrue(h.bootstrapCalls.count >= 1, "repair must bootstrap")
        XCTAssertTrue(result.plistWritten)
        XCTAssertTrue(result.bootstrapped)
    }

    func testRepairOnEnabledMustNotOnlyDelete() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        let result = await h.lifecycle.repair()
        if !result.plistWritten || !result.bootstrapped {
            XCTFail("repair on enabled desired state must reinstall, not merely delete — plistWritten=\(result.plistWritten) bootstrapped=\(result.bootstrapped)")
        }
    }

    func testRepairOnDisabledDisables() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .disabled)
        XCTAssertTrue(h.bootoutCalls.contains(ServeLifecycle.label))
        XCTAssertTrue(h.deletedURLs.contains(h.plistURL))
    }

    // MARK: - restore on failure

    func testBootstrapFailureRestoresPriorPlist() async {
        let h = Harness()
        h.createPlistFile()
        let priorBytes = try! Data(contentsOf: h.plistURL)
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.bootstrapError = ServeLifecycle.BootstrapError(terminationStatus: 1, message: "Bootstrap failed")

        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.plistWritten)
        XCTAssertFalse(result.bootstrapped)

        let restored = try? Data(contentsOf: h.plistURL)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored, priorBytes, "prior plist bytes must be restored on bootstrap failure")
        XCTAssertTrue(result.detail.contains("prior registration restored"))
    }

    func testBootstrapFailureRebootstrapsPriorJob() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.bootstrapError = ServeLifecycle.BootstrapError(terminationStatus: 1, message: "Bootstrap failed")

        let bootstrapBefore = h.bootstrapCalls.count
        _ = await h.lifecycle.repair()
        XCTAssertGreaterThan(h.bootstrapCalls.count, bootstrapBefore, "restore must re-bootstrap the prior job")
    }

    func testPlistWriteFailureRestoresPriorRegistration() async {
        let h = Harness()
        h.createPlistFile()
        let priorBytes = try! Data(contentsOf: h.plistURL)
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.writeError = CocoaError(.fileWriteNoPermission)

        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertFalse(result.plistWritten)

        let restored = try? Data(contentsOf: h.plistURL)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored, priorBytes, "prior plist bytes must be restored on write failure")
        XCTAssertTrue(h.bootstrapCalls.count >= 1, "restore must re-bootstrap prior job")
    }

    func testBootstrapFailureWithNoPriorPlistDeletesNewPlist() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.bootstrapError = ServeLifecycle.BootstrapError(terminationStatus: 1, message: "Bootstrap failed")

        _ = await h.lifecycle.repair()
        XCTAssertTrue(h.deletedURLs.contains(h.plistURL), "when no prior plist existed, the failed new plist must be deleted")
        XCTAssertEqual(h.bootstrapCalls.count, 1, "only one bootstrap attempt (no prior to restore)")
    }

    // MARK: - bounded verify

    func testVerifyReportsRegisteredNeverHealthy() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.jobIsLoaded = true
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertTrue(result.registryVerified)
        XCTAssertFalse(result.detail.lowercased().contains("healthy"), "detail must not claim healthy: \(result.detail)")
        XCTAssertFalse(result.outcome.rawValue.contains("healthy"))
    }

    func testVerifyBoundedByInjectedClockTimeout() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.jobIsLoaded = true
        h.advanceClockBeyond(5.0)
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .enabled)
        let totalSleep: TimeInterval = h.recordedSleeps.reduce(0, +)
        XCTAssertLessThanOrEqual(totalSleep, 10.0, "total sleep must not exceed 10s bound")
    }

    func testVerifyTimeoutReportsUnverified() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.jobIsLoaded = false
        h.advanceClockBeyond(12.0)
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertFalse(result.registryVerified, "verification must fail when job never loads within timeout")
    }

    // MARK: - desired state write failure

    func testEnableDesiredStateWriteFailureReturnsFailed() async {
        let h = Harness()
        h.desiredWriteResult = .failure(ServeDesiredState.Failure(code: "TEST", message: "disk full"))
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertFalse(result.plistWritten)
        XCTAssertTrue(h.bootoutCalls.isEmpty)
    }

    func testDisableDesiredStateWriteFailureReturnsFailed() async {
        let h = Harness()
        h.desiredWriteResult = .failure(ServeDesiredState.Failure(code: "TEST", message: "disk full"))
        let result = await h.lifecycle.disable()
        XCTAssertEqual(result.outcome, .failed)
    }

    // MARK: - no staged bytes removed

    func testEnableDoesNotTouchStagedPath() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        _ = await h.lifecycle.enable()
        XCTAssertFalse(h.deletedURLs.contains(h.canonicalURL), "canonical binary must not be deleted")
    }

    // MARK: - Codable round-trip

    func testConvergenceResultCodableRoundTrip() async throws {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.jobIsLoaded = true
        let result = await h.lifecycle.enable()
        let decoded = try JSONDecoder().decode(ServeLifecycle.ConvergenceResult.self,
                                               from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.outcome, result.outcome)
        XCTAssertEqual(decoded.desiredStateReading, result.desiredStateReading)
        XCTAssertEqual(decoded.canonicalBinaryPath, result.canonicalBinaryPath)
        XCTAssertEqual(decoded.plistWritten, result.plistWritten)
        XCTAssertEqual(decoded.bootstrapped, result.bootstrapped)
        XCTAssertEqual(decoded.registryVerified, result.registryVerified)
    }

    // MARK: - plist encoding

    func testAgentPlistEncodesLaunchdKeys() throws {
        let env = ServeLifecycle.AgentPlist.EnvironmentDict(
            path: "/canonical/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            home: "/Users/test"
        )
        let plist = ServeLifecycle.AgentPlist(
            label: ServeLaunchAgentStatus.label,
            programArguments: ["/canonical/alln", "serve"],
            workingDirectory: "/tmp/probe-scratch",
            standardOutPath: "/tmp/logs/stdout.log",
            standardErrorPath: "/tmp/logs/stderr.log",
            runAtLoad: true,
            environmentVariables: env
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(plist)
        let decoded = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        XCTAssertEqual(decoded?["Label"] as? String, ServeLaunchAgentStatus.label)
        XCTAssertEqual(decoded?["ProgramArguments"] as? [String], ["/canonical/alln", "serve"])
        XCTAssertEqual(decoded?["WorkingDirectory"] as? String, "/tmp/probe-scratch")
        XCTAssertEqual(decoded?["StandardOutPath"] as? String, "/tmp/logs/stdout.log")
        XCTAssertEqual(decoded?["StandardErrorPath"] as? String, "/tmp/logs/stderr.log")
        XCTAssertEqual(decoded?["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(decoded?["ThrottleInterval"] as? Int, 30)
        XCTAssertEqual(decoded?["ProcessType"] as? String, "Background")

        let envVars = decoded?["EnvironmentVariables"] as? [String: String]
        XCTAssertEqual(envVars?["PATH"], "/canonical/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(envVars?["HOME"], "/Users/test")

        let keepAliveDict = decoded?["KeepAlive"] as? [String: Any]
        XCTAssertNotNil(keepAliveDict, "KeepAlive must be a dictionary, not a bare Bool")
        XCTAssertEqual(keepAliveDict?["SuccessfulExit"] as? Bool, false)

        let xmlString = String(data: data, encoding: .utf8)!
        guard let keepAliveRange = xmlString.range(of: "<key>KeepAlive</key>") else {
            XCTFail("KeepAlive key missing from serialized plist")
            return
        }
        let afterKeepAliveKey = xmlString[keepAliveRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(afterKeepAliveKey.hasPrefix("<dict>"),
                       "KeepAlive must serialize as <dict>, got: \(afterKeepAliveKey.prefix(30))")
    }

    func testKeepAliveIsNeverBareTrue() throws {
        let env = ServeLifecycle.AgentPlist.EnvironmentDict(
            path: "/canonical/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            home: "/Users/test"
        )
        let plist = ServeLifecycle.AgentPlist(
            label: ServeLaunchAgentStatus.label,
            programArguments: ["/canonical/alln", "serve"],
            workingDirectory: "/tmp/probe-scratch",
            standardOutPath: "/tmp/logs/stdout.log",
            standardErrorPath: "/tmp/logs/stderr.log",
            environmentVariables: env
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(plist)
        let xmlString = String(data: data, encoding: .utf8)!
        guard let keepAliveKeyRange = xmlString.range(of: "<key>KeepAlive</key>") else {
            XCTFail("KeepAlive key missing")
            return
        }
        let suffix = xmlString[keepAliveKeyRange.upperBound...]
        if let nextKeyRange = suffix.range(of: "<key>") {
            let between = xmlString[keepAliveKeyRange.upperBound..<nextKeyRange.lowerBound]
            XCTAssertFalse(between.contains("<true/>"),
                           "KeepAlive must not serialize as <true/>: \(between)")
        }
        XCTAssertFalse(xmlString.contains("<key>KeepAlive</key><true/>"),
                       "KeepAlive must be a dict, not bare true")
    }

    // MARK: - ConvergenceResult fields

    func testEnabledResultCarriesVerifiedTrueWhenRegistered() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.jobIsLoaded = true
        let result = await h.lifecycle.enable()
        XCTAssertTrue(result.registryVerified)
    }

    func testDisabledResultCarriesVerifiedTrueWhenStopped() async {
        let h = Harness()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        h.jobIsLoaded = false
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .disabled)
        XCTAssertTrue(result.registryVerified)
    }

    // MARK: - Migration: staged → canonical (ASR-S02d)

    func testMigrationDetectedWhenPlistPointsAtStagedPath() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.injectedPlistProgramArgument = h.stagedBinaryURL.path
        h.stagedBytesPresent = true
        h.jobIsLoaded = true

        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertEqual(result.migratedFrom, h.stagedBinaryURL.path)
        XCTAssertTrue(result.stagedBytesRemoved)
        XCTAssertTrue(h.stagedBytesDeletedURLs.contains(h.stagedBinaryURL))
    }

    func testMigrationFollowsOrderedSequence() async {
        let h = Harness()
        h.createPlistFile()

        final class Events: @unchecked Sendable {
            var list: [String] = []
        }
        let events = Events()

        let lifecycle = ServeLifecycle(
            plistURL: h.plistURL,
            bootout: { _ in events.list.append("bootout") },
            plistExists: { _ in true },
            removePlist: { _ in },
            writePlist: { _, _ in events.list.append("write-plist") },
            bootstrap: { _ in events.list.append("bootstrap") },
            homeDirectory: h.homeURL,
            canonicalBinaryURL: h.canonicalURL,
            canonicalBinaryExists: { _ in true },
            readDesiredState: { _ in .present(state: .enabled, updatedAt: Date()) },
            writeDesiredState: { _, _ in .success(()) },
            verifyJobLoaded: { _ in true },
            sleep: { _ in },
            clock: { Date() },
            stagedBinaryURL: h.stagedBinaryURL,
            readExistingPlistProgramArgument: { _ in h.stagedBinaryURL.path },
            stagedBytesExist: { _ in true },
            removeStagedBytes: { _ in events.list.append("remove-staged-bytes") }
        )

        _ = await lifecycle.repair()
        XCTAssertEqual(events.list, ["bootout", "write-plist", "bootstrap", "remove-staged-bytes"],
                       "migration must follow Step 2 order: bootout → write plist → bootstrap → verify → remove staged bytes")
    }

    func testNoMigrationWhenAlreadyCanonical() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.injectedPlistProgramArgument = h.canonicalURL.path
        h.stagedBytesPresent = true
        h.jobIsLoaded = true

        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertNil(result.migratedFrom)
        XCTAssertFalse(result.stagedBytesRemoved)
        XCTAssertTrue(h.stagedBytesDeletedURLs.isEmpty, "staged bytes must not be removed on non-migration path")
    }

    func testMigrationFailureRestoresPriorPlistAndLeavesStagedBytes() async {
        let h = Harness()
        h.createPlistFile()
        let priorBytes = try! Data(contentsOf: h.plistURL)
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.injectedPlistProgramArgument = h.stagedBinaryURL.path
        h.stagedBytesPresent = true
        h.bootstrapError = ServeLifecycle.BootstrapError(terminationStatus: 1, message: "Bootstrap failed")

        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.detail.contains("migration failed"))
        XCTAssertTrue(result.detail.contains("prior registration restored"))
        XCTAssertFalse(result.stagedBytesRemoved)
        XCTAssertTrue(h.stagedBytesDeletedURLs.isEmpty, "staged bytes must remain on failed migration")

        let restored = try? Data(contentsOf: h.plistURL)
        XCTAssertEqual(restored, priorBytes)
    }

    func testMigrationBootoutFailureRestoresAndLeavesStagedBytes() async {
        let h = Harness()
        h.createPlistFile()
        let priorBytes = try! Data(contentsOf: h.plistURL)
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.injectedPlistProgramArgument = h.stagedBinaryURL.path
        h.stagedBytesPresent = true
        h.bootoutError = ServeLifecycle.BootoutError(terminationStatus: 1, message: "Boot-out failed")

        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.detail.contains("migration failed"))
        XCTAssertTrue(result.detail.contains("bootout error"))
        XCTAssertTrue(h.stagedBytesDeletedURLs.isEmpty, "staged bytes must remain after migration bootout failure")
        XCTAssertTrue(h.writtenPlists.isEmpty, "no plist written after migration bootout failure")

        let restored = try? Data(contentsOf: h.plistURL)
        XCTAssertEqual(restored, priorBytes)
    }

    func testMigrationPlistWriteFailureRestoresAndLeavesStagedBytes() async {
        let h = Harness()
        h.createPlistFile()
        let priorBytes = try! Data(contentsOf: h.plistURL)
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.injectedPlistProgramArgument = h.stagedBinaryURL.path
        h.stagedBytesPresent = true
        h.writeError = CocoaError(.fileWriteNoPermission)

        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(h.stagedBytesDeletedURLs.isEmpty)

        let restored = try? Data(contentsOf: h.plistURL)
        XCTAssertEqual(restored, priorBytes)
    }

    func testMigrationVerifyFailureRestoresAndLeavesStagedBytes() async {
        let h = Harness()
        h.createPlistFile()
        let priorBytes = try! Data(contentsOf: h.plistURL)
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.injectedPlistProgramArgument = h.stagedBinaryURL.path
        h.stagedBytesPresent = true
        h.jobIsLoaded = false
        h.advanceClockBeyond(12.0)

        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.detail.contains("migration failed"))
        XCTAssertTrue(result.detail.contains("verify"))
        XCTAssertFalse(result.stagedBytesRemoved)
        XCTAssertTrue(h.stagedBytesDeletedURLs.isEmpty)

        let restored = try? Data(contentsOf: h.plistURL)
        XCTAssertEqual(restored, priorBytes)
    }

    func testMigrationResultReportsMigratedFrom() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.injectedPlistProgramArgument = h.stagedBinaryURL.path
        h.stagedBytesPresent = true
        h.jobIsLoaded = true

        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.migratedFrom, h.stagedBinaryURL.path)
        XCTAssertTrue(result.stagedBytesRemoved)
        XCTAssertTrue(result.detail.contains("migrated from"))
        XCTAssertTrue(result.detail.contains("staged bytes cleaned"))
    }

    func testMigrationReportsStagedBytesLeftWhenRemovalFails() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.injectedPlistProgramArgument = h.stagedBinaryURL.path
        h.stagedBytesPresent = true
        h.stagedRemoveError = CocoaError(.fileWriteNoPermission)
        h.jobIsLoaded = true

        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertEqual(result.migratedFrom, h.stagedBinaryURL.path)
        XCTAssertFalse(result.stagedBytesRemoved)
        XCTAssertTrue(result.detail.contains("staged bytes left on disk"))
    }

    func testDisableNeverRemovesStagedBytes() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        h.stagedBytesPresent = true

        let result = await h.lifecycle.disable()
        XCTAssertEqual(result.outcome, .disabled)
        XCTAssertFalse(result.stagedBytesRemoved)
        XCTAssertTrue(h.stagedBytesDeletedURLs.isEmpty)
    }

    func testRestartNeverRemovesStagedBytes() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.stagedBytesPresent = true

        let result = await h.lifecycle.restart()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertFalse(result.stagedBytesRemoved)
        XCTAssertTrue(h.stagedBytesDeletedURLs.isEmpty)
    }

    func testConvergenceResultCodableRoundTripMigration() async throws {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.injectedPlistProgramArgument = h.stagedBinaryURL.path
        h.stagedBytesPresent = true
        h.jobIsLoaded = true
        let result = await h.lifecycle.repair()
        let decoded = try JSONDecoder().decode(ServeLifecycle.ConvergenceResult.self,
                                               from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.migratedFrom, result.migratedFrom)
        XCTAssertEqual(decoded.stagedBytesRemoved, result.stagedBytesRemoved)
    }
}
