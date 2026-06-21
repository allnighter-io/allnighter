import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// CONT-S0: the per-(thread, source, model, repoRoot) vendor-session store. These are the
/// isolation + persistence guarantees the whole continuity fix rests on.
final class WorkerSessionStoreTests: XCTestCase {

    private func makeStore() -> (ExternalWorkerSessionStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-wss-\(UUID().uuidString)", isDirectory: true)
        return (ExternalWorkerSessionStore(root: root), root)
    }

    private func session(
        thread: String, source: String, model: String, repo: String = "/repo", vendor: String,
        tier: ContinuityTier = .vendorSession
    ) -> ExternalWorkerSession {
        ExternalWorkerSession(
            threadId: thread, sourceId: source, modelId: model, repoRoot: repo,
            vendorSessionId: vendor, continuityTier: tier, createdAt: Date(), lastUsedAt: Date())
    }

    func testUpsertThenGetByKey() {
        let (store, _) = makeStore()
        let s = session(thread: "t1", source: "claude_code", model: "opus", vendor: "v-abc")
        store.upsert(s)
        let got = store.get(s.key)
        XCTAssertEqual(got?.vendorSessionId, "v-abc")
        XCTAssertEqual(store.resumable(s.key)?.vendorSessionId, "v-abc")
    }

    func testUpsertIsIdempotentOnKey() {
        let (store, _) = makeStore()
        store.upsert(session(thread: "t1", source: "claude_code", model: "opus", vendor: "v1"))
        store.upsert(session(thread: "t1", source: "claude_code", model: "opus", vendor: "v2"))
        XCTAssertEqual(store.all(threadId: "t1").count, 1, "same key updates in place, no duplicate")
        XCTAssertEqual(store.get(.init(threadId: "t1", sourceId: "claude_code", modelId: "opus", repoRoot: "/repo"))?.vendorSessionId, "v2")
    }

    func testDifferentThreadsNeverShareAVendorSession() {
        let (store, _) = makeStore()
        store.upsert(session(thread: "t1", source: "claude_code", model: "opus", vendor: "v-t1"))
        store.upsert(session(thread: "t2", source: "claude_code", model: "opus", vendor: "v-t2"))
        XCTAssertEqual(store.get(.init(threadId: "t1", sourceId: "claude_code", modelId: "opus", repoRoot: "/repo"))?.vendorSessionId, "v-t1")
        XCTAssertEqual(store.get(.init(threadId: "t2", sourceId: "claude_code", modelId: "opus", repoRoot: "/repo"))?.vendorSessionId, "v-t2")
    }

    func testModelSwitchForksASeparateRecord() {
        let (store, _) = makeStore()
        store.upsert(session(thread: "t1", source: "claude_code", model: "opus", vendor: "v-opus"))
        store.upsert(session(thread: "t1", source: "claude_code", model: "sonnet", vendor: "v-sonnet"))
        XCTAssertEqual(store.all(threadId: "t1").count, 2, "a model switch is a separate vendor session")
        XCTAssertEqual(store.get(.init(threadId: "t1", sourceId: "claude_code", modelId: "sonnet", repoRoot: "/repo"))?.vendorSessionId, "v-sonnet")
    }

    func testSwitchingSourceDoesNotLeakTheOtherSourceVendorId() {
        let (store, _) = makeStore()
        store.upsert(session(thread: "t1", source: "cursor_agent", model: "composer", vendor: "cursor-chat-1"))
        // A different source on the same thread must resolve to its OWN (absent) session.
        XCTAssertNil(store.resumable(.init(threadId: "t1", sourceId: "grok", modelId: "grok-build", repoRoot: "/repo")),
                     "grok must not inherit cursor's chat id")
    }

    func testReloadedStorePersistsAndStillResumes() {
        let (store, root) = makeStore()
        let s = session(thread: "t1", source: "claude_code", model: "opus", vendor: "v-persist")
        store.upsert(s)
        // A brand-new store over the same root simulates an app reload.
        let reopened = ExternalWorkerSessionStore(root: root)
        XCTAssertEqual(reopened.resumable(s.key)?.vendorSessionId, "v-persist",
                       "a reloaded thread still resumes the same vendor session")
    }

    func testInvalidateStopsResume() {
        let (store, _) = makeStore()
        let s = session(thread: "t1", source: "grok", model: "grok-build", vendor: "v-dead")
        store.upsert(s)
        store.invalidate(s.key)
        XCTAssertNil(store.resumable(s.key), "an invalidated session is not resumable")
        XCTAssertEqual(store.get(s.key)?.status, .invalidated)
    }

    func testPromptContextOnlyIsNeverResumable() {
        let (store, _) = makeStore()
        let s = session(thread: "t1", source: "antigravity", model: "gemini", vendor: "", tier: .promptContextOnly)
        store.upsert(s)
        XCTAssertNil(store.resumable(s.key), "promptContextOnly has no vendor session to resume")
    }

    // CONT-S7: the agent-facing projection (`alln sessions` / `worker_sessions_list`).
    func testWorkerSessionsJSONSortsMostRecentFirstAndRoundTrips() throws {
        var older = session(thread: "t1", source: "claude_code", model: "opus", vendor: "v-old")
        older.lastUsedAt = Date(timeIntervalSince1970: 1000)
        var newer = session(thread: "t1", source: "cursor_agent", model: "composer", vendor: "v-new")
        newer.lastUsedAt = Date(timeIntervalSince1970: 2000)
        let json = WorkerSessionsJSON(threadId: "t1", sessions: [older, newer])
        XCTAssertEqual(json.sessions.map(\.vendorSessionId), ["v-new", "v-old"], "most recent first")
        let data = try JSONEncoder().encode(json)
        XCTAssertEqual(try JSONDecoder().decode(WorkerSessionsJSON.self, from: data), json)
    }
}
