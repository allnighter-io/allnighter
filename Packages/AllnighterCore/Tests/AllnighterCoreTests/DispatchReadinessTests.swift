import XCTest
import AgentOSCLI
import AllnighterCore

final class DispatchReadinessTests: XCTestCase {

    func testVersionChangeInvalidatesCachedVerdict() {
        let stale = ToolProbeRecord(
            driverId: "grok",
            status: .ready(version: "0.2.117"),
            version: "0.2.117",
            lastProbeAt: .distantPast
        )
        let healed = DispatchReadiness.invalidateStaleVersions(
            records: [stale],
            currentVersions: ["grok": "0.2.118"]
        )
        XCTAssertEqual(healed.count, 1)
        XCTAssertEqual(healed[0].version, "0.2.118")
        if case .installedNotProbed(let v) = healed[0].status {
            XCTAssertEqual(v, "0.2.118")
        } else {
            XCTFail("expected installedNotProbed after version change, got \(healed[0].status)")
        }
    }

    func testMatchingVersionLeavesRecordAlone() {
        let ready = ToolProbeRecord(
            driverId: "grok",
            status: .ready(version: "0.2.118"),
            version: "0.2.118",
            lastProbeAt: .distantPast
        )
        let out = DispatchReadiness.invalidateStaleVersions(
            records: [ready],
            currentVersions: ["grok": "0.2.118"]
        )
        XCTAssertEqual(out[0].status, .ready(version: "0.2.118"))
    }

    func testHardBlockOnlyForParkedNotCachedNotInstalled() {
        let model = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both, enabled: true
        )
        XCTAssertNil(DispatchReadiness.hardBlockReason(
            model: model, parkedDriverIds: []
        ))

        // Cached .notInstalled is a sensor reading — inform, never hard-block.
        XCTAssertNil(
            DispatchReadiness.hardBlockReason(model: model, parkedDriverIds: []),
            "parked-empty must not hard-block"
        )

        let parked = DispatchReadiness.hardBlockReason(
            model: model,
            parkedDriverIds: ["grok"]
        )
        XCTAssertNotNil(parked)
        XCTAssertTrue(parked!.contains("parked"))
        XCTAssertTrue(parked!.contains("alln drivers unpark"))
        XCTAssertTrue(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(parked!),
            "parked reason must name a working remediation"
        )
    }

    func testCachedNotInstalledDoesNotHardBlock() {
        let model = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both, enabled: true
        )
        // hardBlockReason no longer consults probe records at all; parked-only.
        XCTAssertNil(
            DispatchReadiness.hardBlockReason(model: model, parkedDriverIds: []),
            "cached notInstalled must never hard-block an explicit pin"
        )
    }

    func testDeadEndDoctorAdviceIsNotAWorkingRemediation() {
        XCTAssertFalse(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(
                "model_grok is notReady — check `alln doctor` (or run `alln doctor --full`); see `alln menu --json`."
            ),
            "check-doctor-only advice is a dead end when doctor already reports OK"
        )
        XCTAssertFalse(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(
                "driver not installed — run `alln detect`, then `alln doctor --full`"
            ),
            "detect-only advice is no longer a pre-dispatch remediation (spawn is the boundary)"
        )
    }

    /// Surviving pre-dispatch refusals must each name a command that can change
    /// the outcome — so this gate cannot be gamed with menu/doctor footers alone.
    func testSurvivingBlockedReasonsAllNameWorkingRemediation() {
        let parked =
            "model_grok driver grok is parked — run `alln drivers unpark grok`, then retry; see `alln menu --json`."
        let disabled =
            "model_grok is disabled — run `alln models enable model_grok`, or pick a ready worker; see `alln menu --json`."
        let unknown =
            "unknown worker id 'model_ghost' for --model — pass a canonical model_* id from `alln models --json` (or `alln menu --json`)."
        let writeLock =
            "an agent is still editing this repo after a long wait — it looks stuck; run `alln ps --json`, then `alln kill <id> --json` if needed, and retry (/tmp/repo)"

        XCTAssertTrue(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(parked),
            "parked"
        )
        XCTAssertTrue(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(disabled),
            "disabled"
        )
        XCTAssertTrue(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(unknown),
            "unknown id"
        )
        XCTAssertTrue(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(writeLock),
            "write lock"
        )
    }

    // MARK: - Inform never blocks (negative / unknown caches)

    /// Founder law: a negative smoke/cache verdict (auth dead, probe failed,
    /// rate-limited, not-yet-probed, notInstalled) must never hard-block an explicit pin.
    func testNegativeCachedVerdictsDoNotHardBlock() {
        let model = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both, enabled: true
        )
        // hardBlockReason is parked-only; any non-parked pin dispatches.
        XCTAssertNil(
            DispatchReadiness.hardBlockReason(model: model, parkedDriverIds: []),
            "any negative/unknown probe cache must not hard-block"
        )
    }

    /// Missing probe cache is unknown — attempt, never invent a veto.
    func testMissingProbeRecordIsUnknownNeverHardBlock() {
        let model = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both, enabled: true
        )
        XCTAssertNil(
            DispatchReadiness.hardBlockReason(model: model, parkedDriverIds: []),
            "nil probe record is unknown — dispatch must be attempted"
        )
    }

    /// Selection surfaces must stay honest: absent probe → notChecked,
    /// negative smoke / notInstalled → notReady — never coerced to ready.
    func testDriversListReportsUnknownHonestlyNeverCoercesToReady() {
        let registry = DriverRegistry([
            DriverManifest(id: "grok", displayName: "Grok", kind: .headlessCLI),
        ])
        let models = [
            Model(id: "model_grok", displayName: "Grok", modelLabel: "grok",
                  driverId: "grok", role: .both, enabled: true),
        ]

        // No probe records → notChecked (unknown).
        let empty = DriverListProjector.build(
            registry: registry, probeRecords: [], models: models, parkedDriverIds: []
        )
        XCTAssertEqual(empty.drivers.first?.status, "notChecked")

        // A CURRENT negative smoke → notReady (informs; does not pretend ready).
        // The timestamp is load-bearing: this fixture used `.distantPast`, which
        // PF-S00 now correctly treats as a verdict that outlived its evidence, so
        // it was really asserting expiry behavior while claiming to assert smoke
        // behavior.
        let negative = DriverListProjector.build(
            registry: registry,
            probeRecords: [
                ToolProbeRecord(
                    driverId: "grok",
                    status: .probeFailed(reason: "auth dead"),
                    lastProbeAt: Date()
                ),
            ],
            models: models,
            parkedDriverIds: []
        )
        XCTAssertEqual(negative.drivers.first?.status, "notReady")

        // And the expiry case it was accidentally covering, now on purpose: an
        // ancient negative stops being asserted (PF-S00) — but it still never
        // becomes ready, which is this test's actual law.
        let stale = DriverListProjector.build(
            registry: registry,
            probeRecords: [
                ToolProbeRecord(
                    driverId: "grok",
                    status: .probeFailed(reason: "auth dead"),
                    lastProbeAt: .distantPast
                ),
            ],
            models: models,
            parkedDriverIds: []
        )
        XCTAssertEqual(stale.drivers.first?.status, "notChecked")
        XCTAssertNotEqual(stale.drivers.first?.status, "ready")

        // Cached notInstalled still informs as notReady — never coerced to ready.
        let notInstalled = DriverListProjector.build(
            registry: registry,
            probeRecords: [
                ToolProbeRecord(
                    driverId: "grok",
                    status: .notInstalled,
                    lastProbeAt: .distantPast
                ),
            ],
            models: models,
            parkedDriverIds: []
        )
        XCTAssertEqual(notInstalled.drivers.first?.status, "notReady")
        XCTAssertEqual(notInstalled.drivers.first?.probeDetail, "Not installed")

        // Genuine ready stays ready.
        let ready = DriverListProjector.build(
            registry: registry,
            probeRecords: [
                ToolProbeRecord(
                    driverId: "grok",
                    status: .ready(version: "0.2.118"),
                    version: "0.2.118",
                    lastProbeAt: .distantPast
                ),
            ],
            models: models,
            parkedDriverIds: []
        )
        XCTAssertEqual(ready.drivers.first?.status, "ready")
    }
}
