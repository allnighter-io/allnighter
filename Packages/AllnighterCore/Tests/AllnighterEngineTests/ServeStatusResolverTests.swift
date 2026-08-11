import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// ASR-S03f1 — every §7 inference ban is a named case that fails when the
/// resolver makes the banned inference. Table first; then the named healthy /
/// degraded / disabled / requiresApproval cases from the work order.
final class ServeStatusResolverTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_720_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_720_000_100)
    private let label = "com.allnighter.resident-coordinator"
    private let canonicalPath = "/Users/me/.local/share/allnighter/bin/alln"
    private let shaA = "abc123"
    private let shaB = "def456"
    private let cdhashA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private let cdhashB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    // MARK: - §7 ban table (write first — every row is a failing case)

    /// Ban: plist exists ⇒ serve is supervised.
    /// Negative proof: plist present, job absent ⇒ degraded.
    func testBan_plistToSupervision_plistPresentJobAbsentIsDegraded() {
        var input = healthyInput()
        input.supervisor.plistPresent = true
        input.supervisor.loaded = false
        input.supervisor.pid = nil
        input.activeHealth = .noResponse(reason: "nothing listening")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertNotNil(status.recovery)
        XCTAssertFalse(status.supervisor.loaded)
    }

    /// Ban: kill(pid, 0) ⇒ health endpoint listening.
    /// Negative proof: recycled live pid, no handshake ⇒ degraded.
    func testBan_pidToDaemon_recycledLivePidWithoutHandshakeIsDegraded() {
        var input = healthyInput()
        input.supervisor.pid = 9999
        input.activeHealth = .noResponse(reason: "connection refused")
        // Durable receipt still names an old daemon; live pid is recycled noise.
        input.receipt = .present(
            daemonId: "old-daemon",
            pid: 9999,
            startedAt: t0,
            rows: requiredRows()
        )
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertNil(status.daemon.activeHealthRespondedAt)
        XCTAssertNotNil(status.recovery)
    }

    /// Ban: process answers ⇒ schedulers work.
    /// Negative proof: missing capacityRefresh row ⇒ degraded.
    func testBan_daemonToScheduler_missingCapacityRefreshIsDegraded() {
        var input = healthyInput()
        input.receipt = .present(
            daemonId: "d1",
            pid: 1234,
            startedAt: t0,
            rows: requiredRows(excluding: "capacityRefresh")
        )
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_SCHEDULER_MISSING")
        XCTAssertFalse(status.schedulers.contains(where: { $0.id == "capacityRefresh" }))
    }

    /// Ban: binary copied ⇒ install succeeded.
    /// Negative proof: desired enabled + path present without active verify ⇒ not healthy.
    func testBan_installToEnabled_pathAloneNeverHealthy() {
        var input = healthyInput()
        input.activeHealth = .noResponse(reason: "not verified after install")
        input.supervisor.loaded = false
        input.supervisor.pid = nil
        let status = ServeStatusJSON.resolve(input)
        XCTAssertNotEqual(status.state, .healthy)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertNotNil(status.recovery)
    }

    /// Ban: update may kill serve at any time.
    /// Negative proof: active obligations ⇒ recovery must not recommend restart.
    func testBan_updateToSafeRestart_activeObligationsRefuseRestartCommand() {
        var input = healthyInput()
        input.activeObligationCount = 2
        input.activeHealth = .noResponse(reason: "wedged")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertNotNil(status.recovery)
        XCTAssertNotEqual(status.recovery?.command, "alln serve restart")
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_BUSY")
    }

    /// Ban: any executable named Allnighter can run serve.
    /// Negative proof: app-bundle binary path never yields healthy / matching identity.
    func testBan_cliToApp_appBundlePathNeverHealthy() {
        var input = healthyInput()
        input.binary.path = "/Applications/Allnighter.app/Contents/MacOS/Allnighter"
        let status = ServeStatusJSON.resolve(input)
        XCTAssertNotEqual(status.state, .healthy)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertFalse(status.binary.matches)
    }

    /// Ban: app-open timer can substitute for serve.
    /// Negative proof: scheduler rows alone (no active handshake) never healthy.
    func testBan_appToFreshness_schedulersWithoutHandshakeNeverHealthy() {
        var input = healthyInput()
        input.activeHealth = .noResponse(reason: "app timer is not serve")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertNil(status.daemon.activeHealthRespondedAt)
    }

    /// Ban: same version string ⇒ same executable.
    /// Negative proof: equal version, different cdhash ⇒ degraded, matches == false.
    func testBan_versionToIdentity_equalVersionDifferentCdhashIsMismatch() {
        var input = healthyInput()
        input.binary.expectedCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: cdhashA, version: "1.0.0")
        input.binary.runningCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: cdhashB, version: "1.0.0")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertFalse(status.binary.matches)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_BINARY_MISMATCH")
    }

    /// ASR-S03f4 failing-first record: pre-fix `runningGitSha: nil` with a live
    /// supervisor yielded `matches: false`, `degraded`, `SERVE_BINARY_IDENTITY_UNRECORDED`,
    /// and `alln install-cli` (a restart that re-enters the same window).
    func testNotYetReportedRunningGitShaIsStartingNotBinaryMismatch() {
        var input = healthyInput()
        input.observedAt = Date(timeIntervalSince1970: 1_720_000_002)
        input.binary.runningGitSha = nil
        input.binary.runningCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: cdhashA, version: "1.0.1")
        input.activeHealth = .noResponse(reason: "first handshake pending")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertTrue(status.binary.matches, "nil running sha must not be read as differs")
        XCTAssertEqual(status.state, .starting)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_STARTING")
        XCTAssertEqual(status.recovery?.command, "alln serve status --json")
        XCTAssertNotEqual(status.recovery?.command, "alln install-cli")
        XCTAssertNotEqual(status.recovery?.reasonCode, "SERVE_BINARY_IDENTITY_UNRECORDED")
    }

    /// ASR-S03f4: not-yet-reported sha alone never sets matches false.
    func testNotYetReportedGitShaNeverSetsMatchesFalse() {
        var input = healthyInput()
        input.binary.runningGitSha = nil
        let status = ServeStatusJSON.resolve(input)
        XCTAssertTrue(status.binary.matches)
    }

    /// ASR-S03f4: handshake matched but git sha not yet in the durable record.
    func testHandshakeMatchedGitShaPendingWithinWindowIsStarting() {
        var input = healthyInput()
        let observed = Date(timeIntervalSince1970: 1_720_000_003)
        input.observedAt = observed
        input.binary.runningGitSha = nil
        input.activeHealth = .responded(daemonId: "d1", pid: 1234, respondedAt: observed)
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .starting)
        XCTAssertTrue(status.binary.matches)
        XCTAssertEqual(status.recovery?.command, "alln serve status --json")
    }

    /// ASR-S03f4 fail-closed: past the §4.3 10s ceiling with no handshake ⇒ degraded.
    func testDaemonNeverAnswersPastCeilingIsDegradedNotStarting() {
        var input = healthyInput()
        input.observedAt = Date(timeIntervalSince1970: 1_720_000_011)
        input.activeHealth = .noResponse(reason: "never answered")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertNotEqual(status.state, .starting)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_UNAVAILABLE")
        XCTAssertNotEqual(status.recovery?.command, "alln install-cli")
    }

    /// ASR-S03f4: stale receipt pid after repair — window anchors to supervisor birth,
    /// not the previous daemon's receipt `startedAt`.
    func testStaleReceiptPidMismatchWithinWindowIsStarting() {
        var input = healthyInput()
        let supervisorBirth = Date(timeIntervalSince1970: 1_720_000_001)
        let observed = Date(timeIntervalSince1970: 1_720_000_003)
        input.observedAt = observed
        input.supervisor.pid = 90565
        input.supervisor.processStartedAt = supervisorBirth
        input.receipt = .present(
            daemonId: "old-daemon",
            pid: 90546,
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            rows: requiredRows()
        )
        input.binary.runningGitSha = nil
        input.activeHealth = .noResponse(reason: "first handshake pending")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .starting)
        XCTAssertTrue(status.binary.matches)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_STARTING")
        XCTAssertEqual(status.recovery?.command, "alln serve status --json")
        XCTAssertNotEqual(status.recovery?.reasonCode, "SERVE_UNAVAILABLE")
    }

    /// ASR-S03f4 fail-closed: stale receipt + supervisor birth past ceiling ⇒ degraded.
    func testStaleReceiptPidMismatchPastCeilingIsDegraded() {
        var input = healthyInput()
        input.observedAt = Date(timeIntervalSince1970: 1_720_000_020)
        input.supervisor.pid = 90565
        input.supervisor.processStartedAt = t0
        input.receipt = .present(
            daemonId: "old-daemon",
            pid: 90546,
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            rows: requiredRows()
        )
        input.activeHealth = .noResponse(reason: "never answered")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_UNAVAILABLE")
        XCTAssertNotEqual(status.state, .starting)
    }

    /// ASR-S03f4 fail-closed: pid mismatch with no supervisor birth observation ⇒ degraded.
    func testStaleReceiptPidMismatchWithoutSupervisorBirthIsDegraded() {
        var input = healthyInput()
        input.observedAt = Date(timeIntervalSince1970: 1_720_000_002)
        input.supervisor.pid = 90565
        input.supervisor.processStartedAt = nil
        input.receipt = .present(
            daemonId: "old-daemon",
            pid: 90546,
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            rows: requiredRows()
        )
        input.activeHealth = .noResponse(reason: "first handshake pending")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_UNAVAILABLE")
    }

    func testDaemonStartupAnchorUsesSupervisorBirthWhenReceiptPidStale() {
        let anchor = ServeStatusJSON.daemonStartupAnchor(
            supervisorPid: 90565,
            supervisorProcessStartedAt: t1,
            receiptPid: 90546,
            receiptStartedAt: t0
        )
        XCTAssertEqual(anchor, t1)
    }

    /// ASR-S03f3: empty/absent expected identity is unrecorded, not a mismatch.
    /// Equal git sha + otherwise healthy ⇒ healthy (reachable-to-green).
    func testUnrecordedExpectedIdentityWithEqualShaIsHealthy() {
        var input = healthyInput()
        input.binary.expectedCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: nil, version: nil)
        input.binary.runningCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: nil, version: "1.0.1")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .healthy)
        XCTAssertTrue(status.binary.matches)
        XCTAssertNil(status.recovery)
        XCTAssertNotEqual(status.recovery?.reasonCode, "SERVE_BINARY_MISMATCH")
    }

    /// ASR-S03f3: version-only identities are not comparable (§7).
    func testVersionOnlyIdentitiesAreUnrecordedNotMismatch() {
        var input = healthyInput()
        input.binary.expectedCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: nil, version: "1.0.1")
        input.binary.runningCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: nil, version: "1.0.1")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(
            ServeStatusJSON.compareCodeIdentity(
                expected: input.binary.expectedCodeIdentity,
                running: input.binary.runningCodeIdentity
            ),
            .unrecorded
        )
        XCTAssertEqual(status.state, .healthy)
        XCTAssertTrue(status.binary.matches)
        XCTAssertNil(status.recovery)
    }

    /// ASR-S03f3: one known cdhash + other side missing ⇒ unrecorded, not differs.
    func testAsymmetricUnrecordedIdentityIsNotMismatch() {
        var input = healthyInput()
        input.binary.expectedCodeIdentity = nil
        input.binary.runningCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: cdhashA, version: "1.0.1")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(
            ServeStatusJSON.compareCodeIdentity(
                expected: input.binary.expectedCodeIdentity,
                running: input.binary.runningCodeIdentity
            ),
            .unrecorded
        )
        XCTAssertEqual(status.state, .healthy)
        XCTAssertTrue(status.binary.matches)
        XCTAssertNotEqual(status.recovery?.reasonCode, "SERVE_BINARY_MISMATCH")
    }

    /// ASR-S03f3: two known differing identities still set MISMATCH + repair.
    func testKnownDifferingIdentitiesStillBinaryMismatch() {
        var input = healthyInput()
        input.binary.expectedCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: cdhashA, version: "1.0.0")
        input.binary.runningCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: cdhashB, version: "1.0.0")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertFalse(status.binary.matches)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_BINARY_MISMATCH")
        XCTAssertEqual(status.recovery?.command, "alln serve repair")
    }

    /// ASR-S03f3: two known differing git shas set MISMATCH even when identity
    /// is unrecorded (nil is never differs for sha, but shaB ≠ shaA is observed).
    func testKnownShaMismatchWithUnrecordedIdentityUsesBinaryMismatch() {
        var input = healthyInput()
        input.binary.expectedCodeIdentity = nil
        input.binary.runningCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: nil, version: "1.0.1")
        input.binary.runningGitSha = shaB
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertFalse(status.binary.matches)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_BINARY_MISMATCH")
        XCTAssertEqual(status.recovery?.command, "alln serve repair")
        XCTAssertNotEqual(status.recovery?.reasonCode, "SERVE_BINARY_IDENTITY_UNRECORDED")
    }

    /// ASR-S03f3: app-bundle path with unrecorded identity names identity-unrecorded
    /// recovery (repair cannot record; install-cli can).
    func testUnrecordedIdentityWithAppBundlePathUsesIdentityUnrecordedRecovery() {
        var input = healthyInput()
        input.binary.path = "/Applications/Allnighter.app/Contents/MacOS/Allnighter"
        input.binary.expectedCodeIdentity = nil
        input.binary.runningCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: nil, version: "1.0.1")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertFalse(status.binary.matches)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_BINARY_IDENTITY_UNRECORDED")
        XCTAssertEqual(status.recovery?.command, "alln install-cli")
        XCTAssertNotEqual(status.recovery?.reasonCode, "SERVE_BINARY_MISMATCH")
    }

    /// ASR-S03f3: correctly installed host with empty install-record identity
    /// is reachable-to-green (not stuck degraded forever).
    func testUnrecordedIdentityReachableToGreen() {
        var input = healthyInput()
        // Live-host shape from the work order: empty expected, version-only running.
        input.binary.expectedCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: nil, version: nil)
        input.binary.runningCodeIdentity = CanonicalCLIInstall.CodeIdentity(cdhash: nil, version: "1.0.1")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .healthy, "unrecorded + equal sha must not stick the host degraded")
        XCTAssertTrue(status.binary.matches)
        XCTAssertNil(status.recovery)
    }

    /// Ban: KeepAlive can always restart safely.
    /// Negative proof: stand-down (loaded, exit 0, no process) ⇒ degraded, not respawn/healthy.
    func testBan_exitToRestart_standDownIsDegradedNotHealthy() {
        var input = healthyInput()
        input.supervisor.loaded = true
        input.supervisor.pid = nil
        input.supervisor.lastExitCode = 0
        input.activeHealth = .noResponse(reason: "deliberate stand-down")
        input.receipt = .present(
            daemonId: "d1",
            pid: 1234,
            startedAt: t0,
            rows: requiredRows(state: .stopped)
        )
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_STAND_DOWN")
        XCTAssertNotEqual(status.state, .disabled)
        XCTAssertNotEqual(status.state, .healthy)
    }

    /// Ban: in-process sleep survives system sleep.
    /// Negative proof: overdue nextWakeAt alone never upgrades to healthy without handshake.
    func testBan_timerToWake_overdueWakeAloneNeverHealthy() {
        var input = healthyInput()
        input.activeHealth = .unknown(reason: "wake observation unknown")
        let overdue = requiredRows()
        input.receipt = .present(
            daemonId: "d1",
            pid: 1234,
            startedAt: t0,
            rows: overdue.map {
                var row = $0
                row.nextWakeAt = Date(timeIntervalSince1970: 1)
                return row
            }
        )
        let status = ServeStatusJSON.resolve(input)
        XCTAssertNotEqual(status.state, .healthy)
        XCTAssertEqual(status.state, .degraded)
    }

    /// Ban: missing process means re-enable it.
    /// Negative proof: disabled / requiresApproval fixtures do not bootstrap.
    func testBan_userDisableToRepair_disabledAndRequiresApprovalDoNotBootstrap() {
        var disabled = healthyInput()
        disabled.desiredState = .known(.disabled)
        disabled.supervisor.loaded = false
        disabled.supervisor.pid = nil
        disabled.activeHealth = .noResponse(reason: "disabled")
        disabled.receipt = .absent
        let disabledStatus = ServeStatusJSON.resolve(disabled)
        XCTAssertEqual(disabledStatus.state, .disabled)
        XCTAssertNil(disabledStatus.recovery)
        XCTAssertNotEqual(disabledStatus.recovery?.command, "alln serve enable")

        var approval = healthyInput()
        approval.supervisor.authorization = .requiresApproval
        approval.supervisor.loaded = false
        approval.supervisor.pid = nil
        approval.activeHealth = .noResponse(reason: "approval revoked")
        let approvalStatus = ServeStatusJSON.resolve(approval)
        XCTAssertEqual(approvalStatus.state, .requiresApproval)
        XCTAssertNotNil(approvalStatus.recovery)
        XCTAssertNotEqual(approvalStatus.recovery?.command, "alln serve repair")
        XCTAssertNotEqual(approvalStatus.recovery?.command, "alln serve enable")
    }

    /// Ban: launchd PATH can answer which vendor CLI to run.
    /// Negative proof: missing optional cloudRelay is omitted — never painted failed / never degrades.
    func testBan_pathToVendor_missingOptionalCloudRelayStillHealthy() {
        var input = healthyInput()
        // required rows only — cloudRelay omitted (PATH never invents it as failed)
        XCTAssertFalse(input.receiptRows().contains(where: { $0.id == "cloudRelay" }))
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .healthy)
        XCTAssertFalse(status.schedulers.contains(where: { $0.id == "cloudRelay" }))
        XCTAssertFalse(status.schedulers.contains(where: { $0.state == .failed }))
    }

    // MARK: - Named cases from work order §9

    func testNamed_plistPresentJobAbsent_degraded() {
        var input = healthyInput()
        input.supervisor.plistPresent = true
        input.supervisor.loaded = false
        input.supervisor.pid = nil
        input.activeHealth = .noResponse(reason: "job absent")
        XCTAssertEqual(ServeStatusJSON.resolve(input).state, .degraded)
    }

    func testNamed_recycledLivePidNoHandshake_degraded() {
        var input = healthyInput()
        input.supervisor.pid = 4242
        input.activeHealth = .noResponse(reason: "no handshake")
        XCTAssertEqual(ServeStatusJSON.resolve(input).state, .degraded)
    }

    func testNamed_equalVersionDifferentCdhash_degradedMatchesFalse() {
        var input = healthyInput()
        input.binary.expectedCodeIdentity = .init(cdhash: cdhashA, version: "9.9.9")
        input.binary.runningCodeIdentity = .init(cdhash: cdhashB, version: "9.9.9")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertFalse(status.binary.matches)
    }

    func testNamed_missingCapacityRefresh_degraded() {
        var input = healthyInput()
        input.receipt = .present(daemonId: "d1", pid: 1234, startedAt: t0,
                                 rows: requiredRows(excluding: "capacityRefresh"))
        XCTAssertEqual(ServeStatusJSON.resolve(input).state, .degraded)
    }

    func testNamed_missingCloudRelay_stillHealthy() {
        let status = ServeStatusJSON.resolve(healthyInput())
        XCTAssertEqual(status.state, .healthy)
        XCTAssertFalse(status.schedulers.contains(where: { $0.id == "cloudRelay" }))
    }

    func testNamed_failedSchedulerRow_degraded() {
        var input = healthyInput()
        var rows = requiredRows()
        rows = rows.map { row in
            var r = row
            if r.id == "notifications" {
                r.state = .failed
                r.lastError = "boom"
            }
            return r
        }
        input.receipt = .present(daemonId: "d1", pid: 1234, startedAt: t0, rows: rows)
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_SCHEDULER_FAILED")
    }

    func testNamed_desiredDisabledNothingLoaded_disabled() {
        var input = healthyInput()
        input.desiredState = .known(.disabled)
        input.supervisor.loaded = false
        input.supervisor.pid = nil
        input.activeHealth = .noResponse(reason: "disabled")
        input.receipt = .absent
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .disabled)
        XCTAssertNil(status.recovery)
    }

    func testNamed_macOSApprovalRevoked_requiresApproval() {
        var input = healthyInput()
        input.supervisor.authorization = .requiresApproval
        input.supervisor.loaded = false
        input.supervisor.pid = nil
        input.activeHealth = .noResponse(reason: "requiresApproval")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .requiresApproval)
        XCTAssertNotNil(status.recovery)
    }

    func testNamed_stoodDownDaemon_degradedNamingStandDownNotDisabled() {
        var input = healthyInput()
        input.supervisor.loaded = true
        input.supervisor.pid = nil
        input.supervisor.lastExitCode = 0
        input.activeHealth = .noResponse(reason: "stand-down")
        input.receipt = .present(daemonId: "d1", pid: 1234, startedAt: t0,
                                 rows: requiredRows(state: .stopped))
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_STAND_DOWN")
        XCTAssertNotEqual(status.state, .disabled)
    }

    // MARK: - healthy unreachable if any of six conditions dropped

    func testHealthyDrop_desiredNotEnabled() {
        var input = healthyInput()
        input.desiredState = .known(.disabled)
        // still loaded — not clean disabled
        XCTAssertNotEqual(ServeStatusJSON.resolve(input).state, .healthy)
    }

    func testHealthyDrop_authorizationNotEnabled() {
        var input = healthyInput()
        input.supervisor.authorization = .unknown
        let status = ServeStatusJSON.resolve(input)
        XCTAssertNotEqual(status.state, .healthy)
        XCTAssertEqual(status.state, .degraded)
    }

    func testHealthyDrop_supervisorNotLoaded() {
        var input = healthyInput()
        input.supervisor.loaded = false
        XCTAssertNotEqual(ServeStatusJSON.resolve(input).state, .healthy)
    }

    func testHealthyDrop_noActiveHealthMatch() {
        var input = healthyInput()
        input.activeHealth = .responded(daemonId: "other", pid: 1234, respondedAt: t1)
        XCTAssertNotEqual(ServeStatusJSON.resolve(input).state, .healthy)
    }

    func testHealthyDrop_binaryMismatch() {
        var input = healthyInput()
        input.binary.runningGitSha = shaB
        XCTAssertNotEqual(ServeStatusJSON.resolve(input).state, .healthy)
        XCTAssertFalse(ServeStatusJSON.resolve(input).binary.matches)
    }

    func testHealthyDrop_missingRequiredScheduler() {
        var input = healthyInput()
        input.receipt = .present(daemonId: "d1", pid: 1234, startedAt: t0,
                                 rows: requiredRows(excluding: "probeRecordRefresh"))
        XCTAssertNotEqual(ServeStatusJSON.resolve(input).state, .healthy)
    }

    // MARK: - recovery non-null for non-healthy non-disabled

    func testRecoveryPresentForDegradedRequiresApprovalStarting() {
        var degraded = healthyInput()
        degraded.activeHealth = .noResponse(reason: "x")
        XCTAssertNotNil(ServeStatusJSON.resolve(degraded).recovery?.reasonCode)
        XCTAssertFalse(ServeStatusJSON.resolve(degraded).recovery?.command.isEmpty ?? true)

        var approval = healthyInput()
        approval.supervisor.authorization = .requiresApproval
        approval.supervisor.loaded = false
        approval.supervisor.pid = nil
        approval.activeHealth = .noResponse(reason: "approval")
        let approvalStatus = ServeStatusJSON.resolve(approval)
        XCTAssertEqual(approvalStatus.state, .requiresApproval)
        XCTAssertNotNil(approvalStatus.recovery?.reasonCode)
        XCTAssertFalse(approvalStatus.recovery?.command.isEmpty ?? true)

        var starting = healthyInput()
        starting.converging = true
        starting.activeHealth = .noResponse(reason: "still starting")
        let startingStatus = ServeStatusJSON.resolve(starting)
        XCTAssertEqual(startingStatus.state, .starting)
        XCTAssertNotNil(startingStatus.recovery?.reasonCode)
        XCTAssertFalse(startingStatus.recovery?.command.isEmpty ?? true)
    }

    func testHealthyHasNilRecovery() {
        let status = ServeStatusJSON.resolve(healthyInput())
        XCTAssertEqual(status.state, .healthy)
        XCTAssertNil(status.recovery)
    }

    // MARK: - unknown fails closed

    func testUnknownDesiredStateFailsClosedDegraded() {
        var input = healthyInput()
        input.desiredState = .unknown(reason: "unreadable")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertTrue(status.recovery?.reasonCode.contains("UNKNOWN") ?? false)
    }

    func testUnknownActiveHealthFailsClosedDegraded() {
        var input = healthyInput()
        input.activeHealth = .unknown(reason: "probe failed")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertTrue(status.recovery?.reasonCode.contains("UNKNOWN") ?? false)
    }

    func testUnknownSupervisorRecoveryNamesRepair() {
        var input = healthyInput()
        input.supervisor.loaded = nil
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_UNKNOWN_SUPERVISOR")
        XCTAssertEqual(status.recovery?.command, "alln serve repair")
        XCTAssertNotEqual(status.recovery?.command, "alln serve status --json")
    }

    func testUnreadableReceiptFailsClosedDegraded() {
        var input = healthyInput()
        input.receipt = .unreadable(reason: "corrupt")
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertNotNil(status.recovery)
    }

    // MARK: - CoreJSON round-trip with §5.2 keys

    func testRoundTrip_exactSection52Keys() throws {
        let status = ServeStatusJSON.resolve(healthyInput())
        let data = try CoreJSON.encode(status)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let topKeys = Set(object.keys)
        XCTAssertEqual(topKeys, [
            "schemaVersion", "desiredState", "state", "supervisor",
            "binary", "daemon", "schedulers", "recovery",
        ])
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)

        let supervisor = try XCTUnwrap(object["supervisor"] as? [String: Any])
        XCTAssertEqual(Set(supervisor.keys), [
            "kind", "label", "loaded", "authorization", "pid", "lastExitCode",
        ])

        let binary = try XCTUnwrap(object["binary"] as? [String: Any])
        XCTAssertEqual(Set(binary.keys), [
            "path", "expectedGitSha", "runningGitSha",
            "expectedCodeIdentity", "runningCodeIdentity", "matches",
        ])

        let daemon = try XCTUnwrap(object["daemon"] as? [String: Any])
        XCTAssertEqual(Set(daemon.keys), [
            "daemonId", "pid", "startedAt", "activeHealthRespondedAt",
        ])

        let decoded = try CoreJSON.decode(ServeStatusJSON.self, from: data)
        XCTAssertEqual(decoded, status)
    }

    func testStoppedRequiredSchedulerUnderLiveDaemonIsDegraded() {
        // One required `.stopped` under a live matching handshake is enough to
        // degrade; recovery must name that scheduler id (not a generic code).
        var input = healthyInput()
        var rows = requiredRows()
        rows = rows.map { row in
            var r = row
            if r.id == "capacityRefresh" { r.state = .stopped }
            return r
        }
        input.receipt = .present(daemonId: "d1", pid: 1234, startedAt: t0, rows: rows)
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_SCHEDULER_STOPPED:capacityRefresh")
    }

    func testStoppedOptionalSchedulerUnderLiveDaemonStaysHealthy() {
        var input = healthyInput()
        var rows = requiredRows()
        rows.append(
            ServeRuntimeReceipts.SchedulerRow(
                id: "cloudRelay",
                state: .stopped,
                lastAttemptAt: t0,
                lastSuccessAt: t0,
                lastError: nil,
                nextWakeAt: t1
            )
        )
        input.receipt = .present(daemonId: "d1", pid: 1234, startedAt: t0, rows: rows)
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .healthy)
        XCTAssertNil(status.recovery)
    }

    func testStoppedRequiredWithoutMatchingHandshakeUnchangedStandDown() {
        // Shutdown / no handshake: stopped rows must not reroute the supervisor
        // stand-down decision that already existed before this slice.
        var input = healthyInput()
        input.supervisor.pid = nil
        input.supervisor.lastExitCode = 0
        input.activeHealth = .noResponse(reason: "stood down")
        input.receipt = .present(daemonId: "d1", pid: 1234, startedAt: t0,
                                 rows: requiredRows(state: .stopped))
        let status = ServeStatusJSON.resolve(input)
        XCTAssertEqual(status.state, .degraded)
        XCTAssertEqual(status.recovery?.reasonCode, "SERVE_STAND_DOWN")
    }

    // MARK: - Fixtures

    private func healthyInput() -> ServeStatusJSON.Input {
        ServeStatusJSON.Input(
            desiredState: .known(.enabled),
            supervisor: .init(
                kind: .launchAgent,
                label: label,
                plistPresent: true,
                loaded: true,
                authorization: .enabled,
                pid: 1234,
                lastExitCode: nil
            ),
            binary: .init(
                path: canonicalPath,
                expectedGitSha: shaA,
                runningGitSha: shaA,
                expectedCodeIdentity: .init(cdhash: cdhashA, version: "1.0.0"),
                runningCodeIdentity: .init(cdhash: cdhashA, version: "1.0.0")
            ),
            activeHealth: .responded(daemonId: "d1", pid: 1234, respondedAt: t1),
            receipt: .present(daemonId: "d1", pid: 1234, startedAt: t0, rows: requiredRows()),
            converging: false,
            observedAt: t1,
            activeObligationCount: 0
        )
    }

    private func requiredRows(
        excluding: String? = nil,
        state: ServeRuntimeReceipts.SchedulerState = .waiting
    ) -> [ServeRuntimeReceipts.SchedulerRow] {
        ServeRuntimeReceipts.requiredSchedulerIds.sorted().compactMap { id in
            if id == excluding { return nil }
            return ServeRuntimeReceipts.SchedulerRow(
                id: id,
                state: state,
                lastAttemptAt: t0,
                lastSuccessAt: t0,
                lastError: nil,
                nextWakeAt: t1
            )
        }
    }
}

private extension ServeStatusJSON.Input {
    func receiptRows() -> [ServeRuntimeReceipts.SchedulerRow] {
        switch receipt {
        case .present(_, _, _, let rows): return rows
        default: return []
        }
    }
}
