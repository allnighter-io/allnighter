import XCTest
import AllnighterCore
@testable import AllnighterCLI

final class MCPPairHandlersTests: XCTestCase {
    func testSliceMissingPacketReturnsToolError() async {
        let runtime = ToolRuntime()
        let outcome = await MCPPairHandlers.slice(runtime: runtime, args: ["project": "prj_test"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "PAIR_SLICE_PACKET_MISSING")
    }

    func testSliceUnknownProjectReturnsToolError() async {
        let runtime = ToolRuntime()
        let packet: [String: Any] = [
            "sliceId": "x",
            "intent": "y",
            "touchAllowlist": ["a.swift"],
            "check": ["method": "command", "command": "true"],
        ]
        let outcome = await MCPPairHandlers.slice(
            runtime: runtime,
            args: ["project": "prj_does_not_exist_zz", "packet": packet]
        )
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "PROJECT_NOT_FOUND")
    }

    func testRegistryAdvertisesPairTools() {
        let names = Set(ContractRegistry.milestone1.mcpTools.map(\.name))
        XCTAssertTrue(names.contains("pair_slice"))
        XCTAssertTrue(names.contains("pair_run"))
        XCTAssertTrue(names.contains("pair_status"))
    }
}
