import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class StallRecoveryServiceTests: XCTestCase {
    private func tempStore() -> (StallEpisodeStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stall-\(UUID().uuidString)")
        return (StallEpisodeStore(rootDirectory: dir), dir)
    }

    private func episode(id: String = UUID().uuidString) -> StallEpisode {
        StallEpisode(
            id: id, projectId: "p1", targetKind: .workerTurn, targetId: UUID().uuidString,
            threadId: UUID().uuidString, status: .active, reason: .runningNoProgress,
            firstDetectedAt: .distantPast, deadlineAnchorAt: .distantPast, thresholdSeconds: 600,
            lastObservableEvent: StallObservableEvent(at: .distantPast, kind: "k", source: "s", summary: "m"),
            primaryAction: "Check status")
    }

    func testKeepWaitingSnoozesAndPersists() throws {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let ep = episode(); try store.save(ep)
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let svc = StallRecoveryService(episodeStore: store, now: { fixed })

        let out = try svc.keepWaiting(episodeId: ep.id, minutes: 30)
        XCTAssertEqual(out.status, .snoozed)
        XCTAssertEqual(out.snoozedUntil, fixed.addingTimeInterval(1800))
        XCTAssertEqual(store.loadAll().first?.status, .snoozed, "persisted")
    }

    func testKeepWaitingRejectsNonPositiveMinutes() throws {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let ep = episode(); try store.save(ep)
        let svc = StallRecoveryService(episodeStore: store)
        XCTAssertThrowsError(try svc.keepWaiting(episodeId: ep.id, minutes: 0)) {
            XCTAssertEqual($0 as? StallRecoveryService.RecoveryError, .invalidMinutes)
        }
    }

    func testDismissClearsWithUserDismiss() throws {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let ep = episode(); try store.save(ep)
        let fixed = Date(timeIntervalSince1970: 2_000_000)
        let svc = StallRecoveryService(episodeStore: store, now: { fixed })

        let out = try svc.dismiss(episodeId: ep.id)
        XCTAssertEqual(out.status, .cleared)
        XCTAssertEqual(out.clearedBy, .userDismiss)
        XCTAssertEqual(out.clearedAt, fixed)
    }

    func testCheckStatusClearsWhenTargetIsGone() throws {
        // The episode points at a thread/turn that does not exist, so a re-check finds
        // nothing stalled → the episode clears (refreshedOut).
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let ep = episode(); try store.save(ep)
        let svc = StallRecoveryService(episodeStore: store, now: { Date(timeIntervalSince1970: 3_000_000) })

        let out = try svc.checkStatus(episodeId: ep.id)
        XCTAssertEqual(out.status, .cleared)
        XCTAssertEqual(out.clearedBy, .refreshedOut)
        XCTAssertNotNil(out.lastRefreshAt)
    }

    func testUnknownEpisodeThrows() {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let svc = StallRecoveryService(episodeStore: store)
        XCTAssertThrowsError(try svc.dismiss(episodeId: "nope")) {
            XCTAssertEqual($0 as? StallRecoveryService.RecoveryError, .episodeNotFound("nope"))
        }
    }
}
