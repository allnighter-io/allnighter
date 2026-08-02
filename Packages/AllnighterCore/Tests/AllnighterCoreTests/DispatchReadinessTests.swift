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
}
