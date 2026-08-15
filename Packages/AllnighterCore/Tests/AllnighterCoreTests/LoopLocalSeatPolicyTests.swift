import XCTest
@testable import AllnighterCore

/// OCL-S07: local Ollama seats may execute, and an explicit `--pm` pin proceeds
/// with disclosure — never a provenance veto.
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

    func testLocalOllamaSeatAsLeadDisclosesAndDoesNotRefuse() {
        XCTAssertTrue(LoopLocalSeatPolicy.isOllamaBacked(local))
        let disclosure = LoopLocalSeatPolicy.localLeadDisclosure(for: local)
        XCTAssertNotNil(disclosure)
        XCTAssertTrue(disclosure?.contains("runs on your Mac through Ollama") == true)
        XCTAssertTrue(disclosure?.contains("You pinned it as the Loop lead") == true)
        XCTAssertFalse(disclosure?.contains("cannot hold") == true)
        XCTAssertFalse(disclosure?.contains("served context window") == true)
    }

    func testLocalLeadDisclosureIncludesServedContextWhenKnown() {
        let snapshot = OllamaLocalRuntimeObserver.Snapshot(
            observedAt: Date(),
            ollamaVersion: "0.32.6",
            residentModels: [
                .init(name: "qwen3:8b", servedContextWindow: 131072)
            ]
        )
        let window = LoopLocalSeatPolicy.servedContextWindow(for: local, snapshot: snapshot)
        XCTAssertEqual(window, 131072)
        let disclosure = LoopLocalSeatPolicy.localLeadDisclosure(
            for: local,
            servedContextWindow: window
        )
        XCTAssertTrue(disclosure?.contains("128K") == true)
    }

    func testUnobservedServedContextIsOmittedNotGuessed() {
        let snapshot = OllamaLocalRuntimeObserver.Snapshot(
            observedAt: Date(),
            ollamaVersion: "0.32.6",
            residentModels: []
        )
        XCTAssertNil(LoopLocalSeatPolicy.servedContextWindow(for: local, snapshot: snapshot))
        XCTAssertNil(LoopLocalSeatPolicy.servedContextWindow(for: local, snapshot: nil))
    }

    func testFrontierAndGoSeatsHaveNoLeadDisclosure() {
        XCTAssertNil(LoopLocalSeatPolicy.localLeadDisclosure(for: frontier))
        XCTAssertNil(LoopLocalSeatPolicy.localLeadDisclosure(for: go))
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
