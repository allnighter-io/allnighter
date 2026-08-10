import XCTest
import AgentOSCLI
@testable import AllnighterCore

final class MenuBenchTallyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNeverScannedMenuPayloadEmitsDetectNextAction() {
        let tally = BenchTallyProjector.tally(
            registry: DriverRegistry([
                DriverManifest(id: "claude_code", displayName: "Claude", kind: .headlessCLI),
            ]),
            records: [],
            now: now
        )
        let payload = MenuJSON.BenchTallyPayload(tally: tally)
        XCTAssertEqual(payload.headline, "neverScanned")
        XCTAssertEqual(payload.nextAction?.command, "alln detect")
        XCTAssertEqual(payload.nextAction?.kind, "detectCLIs")
        XCTAssertEqual(payload.ready, 0)
        XCTAssertEqual(payload.measured, 0)
    }

    func testAllReadyPayloadHasNoNextAction() {
        let tally = BenchTallyProjector.tally(
            registry: DriverRegistry([
                DriverManifest(id: "claude_code", displayName: "Claude", kind: .headlessCLI),
            ]),
            records: [
                ToolProbeRecord(
                    driverId: "claude_code",
                    status: .ready(version: "1"),
                    lastProbeAt: now
                ),
            ],
            now: now
        )
        let payload = MenuJSON.BenchTallyPayload(tally: tally)
        XCTAssertEqual(payload.headline, "allReady")
        XCTAssertNil(payload.nextAction)
        XCTAssertEqual(payload.ready, 1)
    }

    func testPartialPayloadPointsAtDoctorFull() {
        let tally = BenchTallyProjector.tally(
            registry: DriverRegistry([
                DriverManifest(id: "claude_code", displayName: "Claude", kind: .headlessCLI),
                DriverManifest(id: "cursor_agent", displayName: "Cursor", kind: .headlessCLI),
            ]),
            records: [
                ToolProbeRecord(
                    driverId: "claude_code",
                    status: .ready(version: "1"),
                    lastProbeAt: now
                ),
                ToolProbeRecord(
                    driverId: "cursor_agent",
                    status: .notInstalled,
                    lastProbeAt: now
                ),
            ],
            now: now
        )
        let payload = MenuJSON.BenchTallyPayload(tally: tally)
        XCTAssertEqual(payload.headline, "partial")
        XCTAssertEqual(payload.nextAction?.command, "alln doctor --full --json")
        XCTAssertEqual(payload.nextAction?.kind, "runDoctorFull")
    }

    func testMenuProjectEncodesBenchTallyWithoutNullUpdate() throws {
        let payload = MenuJSON.BenchTallyPayload(
            headline: "neverScanned",
            supported: 2, measured: 0, ready: 0,
            needsStep: 0, notInstalled: 0, needsCheck: 2,
            nextAction: AgentSurfaceNextAction(
                kind: "detectCLIs", label: "Find", command: "alln detect"
            )
        )
        let menu = MenuCatalog.project(
            modelEntries: [],
            benchTally: payload
        )
        XCTAssertEqual(menu.benchTally?.headline, "neverScanned")
        XCTAssertEqual(menu.benchTally?.nextAction?.command, "alln detect")
        let data = try MenuCatalog.encodeCompact(menu)
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(raw.contains("\"benchTally\""))
        XCTAssertTrue(raw.contains("neverScanned"))
        XCTAssertTrue(raw.contains("alln detect"))
        XCTAssertFalse(raw.contains("\"update\":null"))
    }

    func testBootstrapPreambleTeachesMenuNextActionForEveryHost() {
        for host in Bootstrap.Host.allCases {
            let preamble = host.coldStartPreamble
            XCTAssertNotNil(preamble, "\(host) must teach cold-start agents")
            XCTAssertTrue(
                preamble!.contains("benchTally.nextAction"),
                "\(host) preamble must name menu nextAction: \(preamble!)"
            )
        }
    }
}
