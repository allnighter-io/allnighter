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

    func testHardBlockOnlyForNotInstalledAndParked() {
        let model = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both, enabled: true
        )
        XCTAssertNil(DispatchReadiness.hardBlockReason(
            model: model,
            record: ToolProbeRecord(
                driverId: "grok", status: .installedNotProbed(version: "1"), lastProbeAt: .distantPast
            ),
            parkedDriverIds: []
        ))
        XCTAssertNil(DispatchReadiness.hardBlockReason(
            model: model, record: nil, parkedDriverIds: []
        ), "missing cache is unknown — never hard-block")

        let notInstalled = DispatchReadiness.hardBlockReason(
            model: model,
            record: ToolProbeRecord(driverId: "grok", status: .notInstalled, lastProbeAt: .distantPast),
            parkedDriverIds: []
        )
        XCTAssertNotNil(notInstalled)
        XCTAssertTrue(DispatchReadiness.blockedReasonNamesWorkingRemediation(notInstalled!))

        let parked = DispatchReadiness.hardBlockReason(
            model: model,
            record: ToolProbeRecord(
                driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast
            ),
            parkedDriverIds: ["grok"]
        )
        XCTAssertNotNil(parked)
        XCTAssertTrue(DispatchReadiness.blockedReasonNamesWorkingRemediation(parked!))
    }

    func testDeadEndDoctorAdviceIsNotAWorkingRemediation() {
        XCTAssertFalse(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(
                "model_grok is notReady — check `alln doctor` (or run `alln doctor --full`); see `alln menu --json`."
            ),
            "check-doctor-only advice is a dead end when doctor already reports OK"
        )
    }

    // MARK: - Inform never blocks (negative / unknown caches)

    /// Founder law: a negative smoke/cache verdict (auth dead, probe failed,
    /// rate-limited, not-yet-probed) must never hard-block an explicit pin.
    func testNegativeCachedVerdictsDoNotHardBlock() {
        let model = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both, enabled: true
        )
        let flow = LoginFlow(interactiveCommand: "grok", instructions: "Sign in.")
        let rateLimited = CapacityObservation(
            kind: .accountRateLimit,
            source: "grok",
            sourceConfidence: .structured,
            rawSnippet: "rate limited",
            observedAt: .distantPast
        )
        let negatives: [ModelSetupStatus] = [
            .installedNotProbed(version: "0.2.117"),
            .installedNotSignedIn(flow),
            .probeFailed(reason: "smoke timed out"),
            .rateLimited(observation: rateLimited),
            .shimmedNeedsConfirm(ToolResolution(
                invocation: .direct(path: "/usr/local/bin/grok"),
                rawCommandV: "/usr/local/bin/grok",
                isAmbiguous: true
            )),
            .ready(version: "0.2.118"),
        ]
        for status in negatives {
            let reason = DispatchReadiness.hardBlockReason(
                model: model,
                record: ToolProbeRecord(driverId: "grok", status: status, lastProbeAt: .distantPast),
                parkedDriverIds: []
            )
            XCTAssertNil(
                reason,
                "status \(status) must not hard-block explicit dispatch; got \(reason ?? "nil")"
            )
        }
    }

    /// Missing probe cache is unknown — attempt, never invent a veto.
    func testMissingProbeRecordIsUnknownNeverHardBlock() {
        let model = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both, enabled: true
        )
        XCTAssertNil(
            DispatchReadiness.hardBlockReason(model: model, record: nil, parkedDriverIds: []),
            "nil probe record is unknown — dispatch must be attempted"
        )
    }

    /// Selection surfaces must stay honest: absent probe → notChecked,
    /// negative smoke → notReady — never coerced to ready to dodge the old veto.
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

        // Negative smoke → notReady (informs; does not pretend ready).
        let negative = DriverListProjector.build(
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
        XCTAssertEqual(negative.drivers.first?.status, "notReady")

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
