import XCTest
@testable import AllnighterCore

/// OCL-S07: local Ollama seats execute; they do not lead.
final class LoopLocalSeatPolicyTests: XCTestCase {
    private let local = Model(
        id: "custom_opencode_ollama_qwen3_8b",
        displayName: "qwen3 8b local",
        modelLabel: "ollama/qwen3:8b",
        driverId: "opencode",
        role: .both
    )
    private let frontier = Model(
        id: "model_opus",
        displayName: "Opus",
        modelLabel: "opus",
        driverId: "claude_code",
        role: .both
    )
    private let go = Model(
        id: "model_opencode_kimi",
        displayName: "Kimi Go",
        modelLabel: "opencode-go/kimi",
        driverId: "opencode",
        role: .both
    )

    func testLocalOllamaSeatCannotHoldPM() {
        XCTAssertTrue(LoopLocalSeatPolicy.isOllamaBacked(local))
        let refusal = LoopLocalSeatPolicy.pmRefusal(for: local)
        XCTAssertNotNil(refusal)
        XCTAssertTrue(refusal?.contains("--dev") == true)
        XCTAssertEqual(LoopLocalSeatPolicy.errorCode, "LOOP_LOCAL_SEAT_CANNOT_LEAD")
    }

    func testFrontierAndGoSeatsMayLead() {
        XCTAssertNil(LoopLocalSeatPolicy.pmRefusal(for: frontier))
        XCTAssertNil(LoopLocalSeatPolicy.pmRefusal(for: go))
        XCTAssertFalse(LoopLocalSeatPolicy.isOllamaBacked(go))
    }

    func testLocalDevWarningNamesWriteLockAndOutcomeHonesty() {
        let warning = LoopLocalSeatPolicy.localExecutionWarning(for: local)
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning?.contains("write lock") == true)
        XCTAssertTrue(warning?.contains("not the seat's report") == true)
        XCTAssertNil(LoopLocalSeatPolicy.localExecutionWarning(for: frontier))
    }
}
