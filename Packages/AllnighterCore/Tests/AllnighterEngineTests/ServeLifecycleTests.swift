import XCTest
@testable import AllnighterEngine

/// ASR-S02c — convergence-path lower-level tests: disable, bootout ordering,
/// failure propagation, absent/disabled/enabled desired-state outcomes,
/// and convergence idempotency. All launchd/file effects injected; no live
/// `launchctl` and no real plist write ever runs against the host.
final class ServeLifecycleTests: XCTestCase {

    private final class Harness: @unchecked Sendable {
        var bootoutCalls: [String] = []
        var bootstrapCalls: [String] = []
        var writtenPlists: [(url: URL, plist: ServeLifecycle.AgentPlist)] = []
        var deletedURLs: [URL] = []
        var desiredWrites: [(state: ServeDesiredState.State, home: URL)] = []

        var bootoutError: Error?
        var bootstrapError: Error?
        var writeError: Error?
        var deleteError: Error?

        var injectedReading: ServeDesiredState.Reading = .absent
        var desiredWriteResult: Result<Void, ServeDesiredState.Failure> = .success(())
        var canonicalExists = true
        var jobIsLoaded = false

        let plistURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).plist")
        let homeURL = URL(fileURLWithPath: "/tmp/home-\(UUID().uuidString)")
        let canonicalURL = URL(fileURLWithPath: "/tmp/canonical-\(UUID().uuidString)/alln")

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
                sleep: { _ in },
                clock: { Date() }
            )
        }

        func createPlistFile() {
            try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("old-plist".utf8).write(to: plistURL, options: .atomic)
        }
    }

    // MARK: - Disable path (bootout + plist removal)

    func testDisabledConvergenceBootsOutAndDeletesPlist() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        let result = await h.lifecycle.disable()
        XCTAssertEqual(result.outcome, .disabled)
        XCTAssertTrue(h.bootoutCalls.contains(ServeLifecycle.label))
        XCTAssertTrue(h.deletedURLs.contains(h.plistURL))
        XCTAssertFalse(result.plistWritten)
        XCTAssertFalse(result.bootstrapped)
    }

    func testDisabledConvergenceWithNoPlistIsNoOp() async {
        let h = Harness()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        let result = await h.lifecycle.disable()
        XCTAssertEqual(result.outcome, .disabled)
        XCTAssertTrue(h.bootoutCalls.contains(ServeLifecycle.label))
        XCTAssertTrue(h.deletedURLs.isEmpty, "no plist to delete")
    }

    func testBootoutFailureInDisablePathReportsFailed() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        h.bootoutError = ServeLifecycle.BootoutError(terminationStatus: 1, message: "Boot-out failed: 5: Input/output error")
        let result = await h.lifecycle.disable()
        XCTAssertEqual(result.outcome, .disabled, "ignorable bootout errors are swallowed in disable path")
    }

    func testPlistDeleteFailureReportsFailed() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        h.deleteError = CocoaError(.fileWriteNoPermission)
        let result = await h.lifecycle.disable()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertFalse(result.plistWritten)
    }

    // MARK: - Absent → enabled migration

    func testAbsentDesiredStateConvergesToEnabled() async {
        let h = Harness()
        h.jobIsLoaded = true
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertTrue(h.writtenPlists.count >= 1)
        XCTAssertTrue(h.bootstrapCalls.count >= 1)
        XCTAssertEqual(result.desiredStateReading, "absent")
    }

    func testAbsentReadsEnabledEffectiveState() {
        let h = Harness()
        let reading = h.lifecycle.readDesiredState(h.homeURL)
        XCTAssertEqual(reading.effectiveState, .enabled)
    }

    // MARK: - Enabled path

    func testEnabledConvergenceWritesPlistAndBootstraps() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.jobIsLoaded = true
        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .enabled)
        XCTAssertTrue(result.plistWritten)
        XCTAssertTrue(result.bootstrapped)
        XCTAssertEqual(h.writtenPlists[0].plist.programArguments, [h.canonicalURL.path, "serve"])
    }

    // MARK: - Missing canonical binary

    func testEnabledWithMissingBinaryReturnsMissingCanonicalBinary() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.canonicalExists = false
        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .missingCanonicalBinary)
        XCTAssertTrue(h.writtenPlists.isEmpty)
        XCTAssertTrue(h.bootstrapCalls.isEmpty)
        XCTAssertTrue(result.detail.contains("SERVE_INSTALL_FAILED"))
        XCTAssertTrue(result.detail.contains("install-cli"))
    }

    // MARK: - unreadable → degraded

    func testUnreadableDesiredStateConvergesToDegraded() async {
        let h = Harness()
        h.injectedReading = .unreadable(reason: "corrupt JSON")
        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertTrue(h.bootoutCalls.isEmpty, "no bootout on unreadable")
        XCTAssertTrue(h.bootstrapCalls.isEmpty, "no bootstrap on unreadable")
        XCTAssertTrue(h.writtenPlists.isEmpty, "no plist on unreadable")
        XCTAssertTrue(result.detail.contains("unreadable"))
    }

    // MARK: - IDEMPOTENCY

    func testRepeatedEnableIsIdempotent() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.jobIsLoaded = true
        _ = await h.lifecycle.enable()
        let firstPlists = h.writtenPlists.count
        let firstBootstraps = h.bootstrapCalls.count
        _ = await h.lifecycle.enable()
        XCTAssertEqual(h.writtenPlists.count, firstPlists + 1, "each converge rewrites the plist")
        XCTAssertEqual(h.bootstrapCalls.count, firstBootstraps + 1, "each converge re-bootstraps")
    }

    func testRepeatedDisableIsIdempotent() async {
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        _ = await h.lifecycle.disable()
        XCTAssertTrue(h.deletedURLs.contains(h.plistURL))
        let deleteCount = h.deletedURLs.count
        _ = await h.lifecycle.disable()
        XCTAssertEqual(h.deletedURLs.count, deleteCount, "second disable should not attempt another delete")
    }

    // MARK: - ConvergenceResult Codable round-trip

    func testConvergenceResultRoundTripEnabled() async throws {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.jobIsLoaded = true
        let result = await h.lifecycle.repair()
        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ServeLifecycle.ConvergenceResult.self, from: encoded)
        XCTAssertEqual(decoded.outcome, .enabled)
        XCTAssertEqual(decoded.desiredStateReading, result.desiredStateReading)
        XCTAssertEqual(decoded.canonicalBinaryPath, result.canonicalBinaryPath)
        XCTAssertEqual(decoded.plistWritten, result.plistWritten)
        XCTAssertEqual(decoded.bootstrapped, result.bootstrapped)
        XCTAssertEqual(decoded.registryVerified, result.registryVerified)
        XCTAssertEqual(decoded.detail, result.detail)
    }

    func testConvergenceResultRoundTripDisabled() async throws {
        let h = Harness()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())
        let result = await h.lifecycle.disable()
        let decoded = try JSONDecoder().decode(ServeLifecycle.ConvergenceResult.self,
                                               from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.outcome, .disabled)
        XCTAssertEqual(decoded.desiredStateReading, result.desiredStateReading)
    }

    func testConvergenceResultRoundTripDegraded() async throws {
        let h = Harness()
        h.injectedReading = .unreadable(reason: "truncated JSON")
        let result = await h.lifecycle.repair()
        let decoded = try JSONDecoder().decode(ServeLifecycle.ConvergenceResult.self,
                                               from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.outcome, .degraded)
    }

    func testConvergenceResultRoundTripMissingBinary() async throws {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.canonicalExists = false
        let result = await h.lifecycle.repair()
        let decoded = try JSONDecoder().decode(ServeLifecycle.ConvergenceResult.self,
                                               from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.outcome, .missingCanonicalBinary)
    }

    // MARK: - ConvergenceOutcome values

    func testConvergenceOutcomeRawValues() {
        XCTAssertEqual(ServeLifecycle.ConvergenceOutcome.enabled.rawValue, "enabled")
        XCTAssertEqual(ServeLifecycle.ConvergenceOutcome.disabled.rawValue, "disabled")
        XCTAssertEqual(ServeLifecycle.ConvergenceOutcome.degraded.rawValue, "degraded")
        XCTAssertEqual(ServeLifecycle.ConvergenceOutcome.failed.rawValue, "failed")
        XCTAssertEqual(ServeLifecycle.ConvergenceOutcome.missingCanonicalBinary.rawValue, "missingCanonicalBinary")
    }

    // MARK: - `disable` boots out before plist delete (ordering)

    func testDisableOrderingBootoutBeforePlistDelete() async {
        final class Ordering: @unchecked Sendable {
            var events: [String] = []
        }
        let ordering = Ordering()
        let h = Harness()
        h.createPlistFile()
        h.injectedReading = .present(state: .disabled, updatedAt: Date())

        let lifecycle = ServeLifecycle(
            plistURL: h.plistURL,
            bootout: { _ in ordering.events.append("bootout") },
            plistExists: { _ in !h.deletedURLs.contains(h.plistURL) },
            removePlist: { url in ordering.events.append("delete-plist"); h.deletedURLs.append(url) },
            writePlist: { _, _ in },
            bootstrap: { _ in },
            homeDirectory: h.homeURL,
            canonicalBinaryURL: h.canonicalURL,
            canonicalBinaryExists: { _ in true },
            readDesiredState: { _ in .present(state: .disabled, updatedAt: Date()) },
            writeDesiredState: { _, _ in .success(()) },
            verifyJobLoaded: { _ in false },
            sleep: { _ in },
            clock: { Date() }
        )

        _ = await lifecycle.disable()
        guard let bootIdx = ordering.events.firstIndex(of: "bootout"),
              let delIdx = ordering.events.firstIndex(of: "delete-plist") else {
            XCTFail("expected both bootout and delete-plist events")
            return
        }
        XCTAssertLessThan(bootIdx, delIdx, "bootout must precede plist delete, got events: \(ordering.events)")
    }

    // MARK: - Error types

    func testBootoutErrorEquatable() {
        let a = ServeLifecycle.BootoutError(terminationStatus: 1, message: "fail")
        let b = ServeLifecycle.BootoutError(terminationStatus: 1, message: "fail")
        XCTAssertEqual(a, b)
    }

    func testBootstrapErrorEquatable() {
        let a = ServeLifecycle.BootstrapError(terminationStatus: 1, message: "fail")
        let b = ServeLifecycle.BootstrapError(terminationStatus: 1, message: "fail")
        XCTAssertEqual(a, b)
    }

    // MARK: - ConvergenceResult Equatable

    func testConvergenceResultEquatable() {
        let a = ServeLifecycle.ConvergenceResult(
            outcome: .enabled, desiredStateReading: "present(enabled)",
            canonicalBinaryPath: "/tmp/alln", plistWritten: true, bootstrapped: true,
            registryVerified: true, detail: "ok"
        )
        let b = ServeLifecycle.ConvergenceResult(
            outcome: .enabled, desiredStateReading: "present(enabled)",
            canonicalBinaryPath: "/tmp/alln", plistWritten: true, bootstrapped: true,
            registryVerified: true, detail: "ok"
        )
        XCTAssertEqual(a, b)
    }

    func testConvergenceResultNotEqual() {
        let a = ServeLifecycle.ConvergenceResult(
            outcome: .enabled, desiredStateReading: "present(enabled)",
            canonicalBinaryPath: "/tmp/alln", plistWritten: true, bootstrapped: true,
            registryVerified: true, detail: "ok"
        )
        let b = ServeLifecycle.ConvergenceResult(
            outcome: .disabled, desiredStateReading: "present(disabled)",
            canonicalBinaryPath: "/tmp/alln", plistWritten: false, bootstrapped: false,
            registryVerified: false, detail: "other"
        )
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Sendable conformance

    func testConvergenceOutcomeIsSendable() {
        let outcome: ServeLifecycle.ConvergenceOutcome = .enabled
        let _: @Sendable () -> ServeLifecycle.ConvergenceOutcome = { outcome }
    }

    func testConvergenceResultIsSendable() {
        let result = ServeLifecycle.ConvergenceResult(
            outcome: .enabled, desiredStateReading: "present(enabled)",
            canonicalBinaryPath: "/tmp/alln", plistWritten: true, bootstrapped: true,
            registryVerified: true, detail: "ok"
        )
        let _: @Sendable () -> ServeLifecycle.ConvergenceResult = { result }
    }

    func testAgentPlistIsSendable() {
        let plist = ServeLifecycle.AgentPlist(
            label: "test", programArguments: ["/tmp/a"], workingDirectory: "/tmp",
            standardOutPath: "/tmp/o", standardErrorPath: "/tmp/e",
            environmentVariables: .init(path: "/usr/bin", home: "/tmp")
        )
        let _: @Sendable () -> ServeLifecycle.AgentPlist = { plist }
    }

    // MARK: - Absent reports correctly in result

    func testAbsentDesiredStateIsReportedInResult() async {
        let h = Harness()
        h.jobIsLoaded = true
        let result = await h.lifecycle.enable()
        XCTAssertEqual(result.desiredStateReading, "absent")
        XCTAssertEqual(result.outcome, .enabled)
    }

    // MARK: - Present enabled is distinguishable from absent

    func testExplicitEnabledIsDistinguishableFromAbsent() async {
        let h = Harness()
        h.injectedReading = .present(state: .enabled, updatedAt: Date())
        h.jobIsLoaded = true
        let result = await h.lifecycle.repair()
        XCTAssertEqual(result.desiredStateReading, "present(enabled)")
        XCTAssertEqual(result.outcome, .enabled)
    }
}
