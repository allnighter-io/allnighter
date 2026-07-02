import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// F2_B.3c: the `health == runs` invocation-resolution behavior this file used to
/// prove directly against `WorkerRunner` (direct path / bare command / login-shell
/// alias) now lives in `SpawnResolvingCommandRunner`, already covered end-to-end by
/// `SpawnResolvingCommandRunnerTests` — those three cases were retired here as
/// redundant, not silently dropped. `testSetupStorePersistsAssembledTeam` below is
/// unrelated to worker invocation (it predates this file's `WorkerRunner` focus) and
/// is kept as-is.
final class WorkerRunnerInvocationTests: XCTestCase {
    func testSetupStorePersistsAssembledTeam() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("setup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SetupStore(fileURL: url)
        let assembled = TeamAssembler.Assembled(
            benchModelIds: ["model_opus"], workerSpecs: [WorkerSpec(modelId: "model_opus")],
            planWriterModelId: "model_opus", assembledAt: Date(timeIntervalSince1970: 0))
        try store.save(.init(records: [], setupCompletedAt: nil, assembledTeam: assembled))
        XCTAssertEqual(store.load().assembledTeam, assembled)
    }
}
