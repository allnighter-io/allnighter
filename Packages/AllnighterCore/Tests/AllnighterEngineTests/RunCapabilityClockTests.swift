import XCTest
import AllnighterCore
import AgentOSCLI
@testable import AllnighterEngine

/// PF-S03b — the writer that was missing. `SourceProbeService`'s cheap path
/// cannot honestly advance `lastProbeAt` (Probe_Freshness.md's stall); a
/// completed REAL run is better evidence than a probe and costs nothing
/// extra. This exercises `RunCapabilityClock.apply` directly (pure, no
/// `RunService` plumbing needed) against the exact `WorkerAnswerErrorKind`
/// taxonomy the packet names.
final class RunCapabilityClockTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func manifest(loginFlow: LoginFlow? = nil) -> DriverManifest {
        DriverManifest(
            id: "kimi", displayName: "Kimi", kind: .headlessCLI,
            setup: SetupBlock(bins: ["kimi"], knownPaths: [], loginFlow: loginFlow)
        )
    }

    private func done(output: String = "ok") -> WorkerRunResult {
        WorkerRunResult(status: .done, output: output)
    }

    private func failed(_ kind: WorkerAnswerErrorKind) -> WorkerRunResult {
        WorkerRunResult(status: .failed, errorKind: kind)
    }

    // MARK: - Success confirms capability

    /// A successful run with no prior record at all creates a fresh
    /// `.ready` record — "confirmed at T", the strongest of the three states.
    func testSuccessfulRunConfirmsCapabilityFromNoPriorRecord() throws {
        let merged = try XCTUnwrap(RunCapabilityClock.apply(
            driverId: "kimi", manifest: manifest(), result: done(), now: now, records: []))
        let record = try XCTUnwrap(merged.first { $0.driverId == "kimi" })
        XCTAssertEqual(record.status, .ready(version: ""))
        XCTAssertEqual(record.lastProbeAt, now)
        XCTAssertEqual(record.lastDetectedAt, now)
        XCTAssertEqual(record.resolvedBy, "RunService")
    }

    /// A successful run over an existing record advances the clock AND
    /// clears a stale negative — the whole point: fifty successful invocations
    /// is stronger evidence than one probe from days ago.
    func testSuccessfulRunAdvancesCapabilityClockOverAStaleNegative() throws {
        let stale = ToolProbeRecord(
            driverId: "kimi", status: .probeFailed(reason: "timeout"),
            lastProbeAt: now.addingTimeInterval(-3600 * 40))
        let merged = try XCTUnwrap(RunCapabilityClock.apply(
            driverId: "kimi", manifest: manifest(), result: done(), now: now, records: [stale]))
        let record = try XCTUnwrap(merged.first { $0.driverId == "kimi" })
        XCTAssertEqual(record.status, .ready(version: ""))
        XCTAssertEqual(record.lastProbeAt, now)
        XCTAssertEqual(record.lastDetectedAt, now)
    }

    /// A successful run preserves the version string a real probe already
    /// established — the run does not know the CLI's version, so it must not
    /// clobber known evidence with a blank.
    func testSuccessfulRunPreservesKnownVersion() throws {
        let existing = ToolProbeRecord(
            driverId: "kimi", status: .ready(version: "1.2.3"), version: "1.2.3",
            lastProbeAt: now.addingTimeInterval(-600), lastDetectedAt: now.addingTimeInterval(-600))
        let merged = try XCTUnwrap(RunCapabilityClock.apply(
            driverId: "kimi", manifest: manifest(), result: done(), now: now, records: [existing]))
        let record = try XCTUnwrap(merged.first { $0.driverId == "kimi" })
        XCTAssertEqual(record.status, .ready(version: "1.2.3"))
    }

    // MARK: - Negatives

    func testMissingCLIRecordsNotInstalled() throws {
        let merged = try XCTUnwrap(RunCapabilityClock.apply(
            driverId: "kimi", manifest: manifest(), result: failed(.missingCLI), now: now, records: []))
        let record = try XCTUnwrap(merged.first { $0.driverId == "kimi" })
        XCTAssertEqual(record.status, .notInstalled)
        XCTAssertEqual(record.lastProbeAt, now)
        XCTAssertEqual(record.lastDetectedAt, now)
        XCTAssertEqual(record.resolvedBy, "RunService")
    }

    /// `authRequired` uses the SAME manifest-declared login flow the detector
    /// would — never a locally-invented one.
    func testAuthRequiredRecordsInstalledNotSignedInUsingManifestLoginFlow() throws {
        let flow = LoginFlow(interactiveCommand: "kimi", instructions: "Run `kimi login`.")
        let merged = try XCTUnwrap(RunCapabilityClock.apply(
            driverId: "kimi", manifest: manifest(loginFlow: flow), result: failed(.authRequired),
            now: now, records: []))
        let record = try XCTUnwrap(merged.first { $0.driverId == "kimi" })
        XCTAssertEqual(record.status, .installedNotSignedIn(flow))
    }

    /// No manifest / no declared login flow: still writes a negative, never
    /// nothing — but without fabricating a `LoginFlow` it does not have.
    func testAuthRequiredWithNoManifestLoginFlowFallsBackToProbeFailed() throws {
        let merged = try XCTUnwrap(RunCapabilityClock.apply(
            driverId: "kimi", manifest: manifest(loginFlow: nil), result: failed(.authRequired),
            now: now, records: []))
        let record = try XCTUnwrap(merged.first { $0.driverId == "kimi" })
        XCTAssertEqual(record.status, .probeFailed(reason: "auth required"))
    }

    // MARK: - Fail closed: not readiness evidence

    /// `timedOut`, `nonzeroExit`, `emptyOutput`, `cancelled`, `permissionRequired`
    /// — none of these speak to whether the seat works. No write at all: `nil`,
    /// not an unchanged-but-recomputed record, so a caller can skip persistence.
    func testNonEvidenceOutcomesWriteNothing() {
        let kinds: [WorkerAnswerErrorKind] = [
            .timedOut, .nonzeroExit, .emptyOutput, .cancelled, .permissionRequired,
        ]
        for kind in kinds {
            let result = RunCapabilityClock.apply(
                driverId: "kimi", manifest: manifest(), result: failed(kind), now: now, records: [])
            XCTAssertNil(result, "\(kind) must yield no observation")
        }
    }

    /// The same non-evidence outcomes must leave an EXISTING record
    /// completely untouched when a caller mistakenly still tries to persist —
    /// belt and suspenders on top of the `nil` contract above.
    func testNonEvidenceOutcomeDoesNotMutateExistingRecordIfSomehowApplied() {
        let existing = ToolProbeRecord(
            driverId: "kimi", status: .ready(version: "1.0"),
            lastProbeAt: now.addingTimeInterval(-600), lastDetectedAt: now.addingTimeInterval(-600))
        let result = RunCapabilityClock.apply(
            driverId: "kimi", manifest: manifest(), result: failed(.nonzeroExit), now: now,
            records: [existing])
        XCTAssertNil(result)
    }

    // MARK: - Untouched drivers

    /// A write for one driver must never disturb another driver's record.
    func testWriteForOneDriverLeavesOthersUntouched() throws {
        let other = ToolProbeRecord(
            driverId: "grok", status: .ready(version: "9.9"),
            lastProbeAt: now.addingTimeInterval(-100), lastDetectedAt: now.addingTimeInterval(-100))
        let merged = try XCTUnwrap(RunCapabilityClock.apply(
            driverId: "kimi", manifest: manifest(), result: done(), now: now, records: [other]))
        let untouched = try XCTUnwrap(merged.first { $0.driverId == "grok" })
        XCTAssertEqual(untouched, other)
    }
}
