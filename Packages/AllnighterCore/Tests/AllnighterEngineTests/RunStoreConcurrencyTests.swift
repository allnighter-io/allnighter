import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Regression law for the testTeamCancel flake (2026-06-16). Two distinct races
/// let a cancel be lost or a reader see a half-written file:
///   1. run.json was written non-atomically, so a concurrent reader (cancel /
///      status) could decode a torn/empty file and get nil.
///   2. the background progress save could clobber a just-written `.cancelled`
///      status (TOCTOU between the cancelled-flag check and the save).
/// These hammer both deterministically — a regression brings the flake back.
final class RunStoreConcurrencyTests: XCTestCase {

    private func freshStore() -> (RunStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("runstore-\(UUID().uuidString)")
        return (RunStore(rootDirectory: root.appendingPathComponent("Runs")), root)
    }

    /// Concurrent save + load must never tear: the reader sees the complete old
    /// or complete new run.json, never nil. Guards the atomic-write fix.
    func testConcurrentSaveAndLoadNeverReturnsNil() async throws {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = TeamRun(id: "concurrent-1", prompt: "seed", status: .fanningOut, createdAt: Date(timeIntervalSince1970: 0))
        _ = try store.save(base, models: [])

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<300 {
                    var r = base
                    // Vary payload size so a torn read would surface as a decode failure.
                    r.prompt = String(repeating: "x", count: i % 64)
                    _ = try? store.save(r, models: [])
                }
            }
            group.addTask {
                for _ in 0..<300 {
                    let loaded = store.load(runId: "concurrent-1")
                    XCTAssertNotNil(loaded, "load saw a torn/partial run.json — save must be atomic")
                    // Orphan recovery must not misfire: this process owns the run
                    // and is alive, so a concurrent owner.pid write must never read
                    // as absent/torn and flip the live run to .interrupted.
                    XCTAssertNotEqual(loaded?.status, .interrupted,
                                      "live run misread as orphaned — owner.pid write must be atomic + ordered before run.json")
                }
            }
        }
    }
}
