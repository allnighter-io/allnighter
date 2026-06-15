import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// Context assembly: provenance, strategies, caps, and visible truncation
/// (PWT-S04). No estimated tokens anywhere.
final class ThreadContextBuilderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 0)

    private func thread(_ turns: [ThreadTurn], workingDir: String? = nil) -> WorkThread {
        WorkThread(id: "t1", title: "Team accounts", createdAt: now, updatedAt: now,
                   workingDir: workingDir, turns: turns)
    }

    private func user(_ id: String, _ text: String) -> ThreadTurn {
        ThreadTurn(id: id, threadId: "t1", kind: .userMessage, status: .done,
                   createdAt: now, author: .user, text: text)
    }

    private func reply(_ id: String, _ text: String, worker: String = "model_opus") -> ThreadTurn {
        ThreadTurn(id: id, threadId: "t1", kind: .workerChat, status: .done,
                   createdAt: now, author: .worker, text: text, workerId: worker)
    }

    func testRecentTurnsPreserveProvenance() {
        let builder = ThreadContextBuilder()
        let t = thread([user("u1", "first question"), reply("r1", "first answer", worker: "model_grok")])
        let packet = builder.build(thread: t, latestMessage: "follow up", turnId: "u2",
                                   packetId: "p1", now: now)
        XCTAssertEqual(packet.strategy, .recentTurns)
        XCTAssertTrue(packet.text.contains("Thread: Team accounts"))
        XCTAssertTrue(packet.text.contains("User: first question"))
        XCTAssertTrue(packet.text.contains("model_grok: first answer"))
        XCTAssertTrue(packet.text.contains("Latest user message:\nfollow up"))
        XCTAssertEqual(packet.includedTurnIds, ["u1", "r1"])
        XCTAssertFalse(packet.truncated)
    }

    func testWorkingDirInHeader() {
        let builder = ThreadContextBuilder()
        let t = thread([user("u1", "hi")], workingDir: "/Users/mike/Code/acme")
        let packet = builder.build(thread: t, latestMessage: "go", turnId: "u2", packetId: "p1", now: now)
        XCTAssertTrue(packet.text.contains("(workingDir: /Users/mike/Code/acme)"))
    }

    func testRecentTurnsCapEmitsVisibleTruncation() {
        let builder = ThreadContextBuilder()
        let turns = (1...10).map { user("u\($0)", "msg \($0)") }
        let opts = ThreadContextBuilder.Options(strategy: .recentTurns, maxTurns: 3)
        let packet = builder.build(thread: thread(turns), latestMessage: "now", turnId: "x",
                                   packetId: "p1", now: now, options: opts)
        XCTAssertTrue(packet.truncated)
        XCTAssertEqual(packet.truncationNote, "included last 3 turns; 7 older omitted")
        XCTAssertEqual(packet.includedTurnIds, ["u8", "u9", "u10"])
        XCTAssertFalse(packet.text.contains("msg 7"))   // omitted
        XCTAssertTrue(packet.text.contains("msg 8"))    // first kept
        XCTAssertTrue(packet.text.contains("msg 10"))
    }

    func testExplicitSelectionOnlyIncludesChosenTurns() {
        let builder = ThreadContextBuilder()
        let t = thread([user("u1", "alpha"), reply("r1", "beta"), user("u2", "gamma")])
        let opts = ThreadContextBuilder.Options(strategy: .explicitSelection, selectedTurnIds: ["r1"])
        let packet = builder.build(thread: t, latestMessage: "q", turnId: "x",
                                   packetId: "p1", now: now, options: opts)
        XCTAssertEqual(packet.strategy, .explicitSelection)
        XCTAssertEqual(packet.includedTurnIds, ["r1"])
        XCTAssertTrue(packet.text.contains("Quoted / selected:"))
        XCTAssertTrue(packet.text.contains("beta"))
        XCTAssertFalse(packet.text.contains("alpha"))
    }

    func testAttachedFileResolvedAgainstWorkingDirAndCapped() {
        let big = String(repeating: "X", count: 5_000)
        let reader: @Sendable (String) -> String? = { path in
            path == "/wd/notes.txt" ? big : nil
        }
        let builder = ThreadContextBuilder(fileReader: reader)
        let t = thread([user("u1", "hi")], workingDir: "/wd")
        let opts = ThreadContextBuilder.Options(attachedFiles: ["notes.txt"], fileByteCap: 100)
        let packet = builder.build(thread: t, latestMessage: "go", turnId: "x",
                                   packetId: "p1", now: now, options: opts)
        XCTAssertEqual(packet.includedFiles, ["notes.txt"])
        XCTAssertTrue(packet.truncated)
        XCTAssertTrue(packet.text.contains("… (truncated)"))
        XCTAssertNotNil(packet.truncationNote)
    }

    func testUnreadableFileNoted() {
        let builder = ThreadContextBuilder(fileReader: { _ in nil })
        let t = thread([user("u1", "hi")], workingDir: "/wd")
        let opts = ThreadContextBuilder.Options(attachedFiles: ["ghost.txt"])
        let packet = builder.build(thread: t, latestMessage: "go", turnId: "x",
                                   packetId: "p1", now: now, options: opts)
        XCTAssertTrue(packet.text.contains("ghost.txt: (unreadable)"))
        XCTAssertTrue(packet.includedFiles.isEmpty)
    }

    func testInThreadArtifactsIncludedWithRunIds() {
        let builder = ThreadContextBuilder()
        var teamRun = ThreadTurn(id: "c1", threadId: "t1", kind: .teamRun, status: .done,
                                 createdAt: now, author: .system, runId: "run_9")
        teamRun.artifactRefs = [ArtifactRef(kind: .plan, runId: "run_9", excerpt: "Phase 1")]
        let packet = builder.build(thread: thread([user("u1", "hi"), teamRun]),
                                   latestMessage: "go", turnId: "x", packetId: "p1", now: now)
        XCTAssertTrue(packet.text.contains("Relevant artifacts:"))
        XCTAssertTrue(packet.text.contains("master_plan — from run run_9 — “Phase 1”"))
        XCTAssertEqual(packet.includedRunIds, ["run_9"])
    }

    func testOverallByteCapKeepsHeaderAndLatestMessage() {
        let builder = ThreadContextBuilder()
        let turns = (1...20).map { user("u\($0)", String(repeating: "y", count: 500)) }
        let opts = ThreadContextBuilder.Options(byteCap: 400, maxTurns: 20)
        let packet = builder.build(thread: thread(turns), latestMessage: "THE-LATEST",
                                   turnId: "x", packetId: "p1", now: now, options: opts)
        XCTAssertTrue(packet.truncated)
        XCTAssertTrue(packet.text.contains("Thread: Team accounts"))
        XCTAssertTrue(packet.text.contains("Latest user message:\nTHE-LATEST"))
    }

    func testNoTokenEstimatesAnywhere() {
        let builder = ThreadContextBuilder()
        let packet = builder.build(thread: thread([user("u1", "hi")]),
                                   latestMessage: "go", turnId: "x", packetId: "p1", now: now)
        let lowered = packet.text.lowercased()
        XCTAssertFalse(lowered.contains("token"))
        // byteCount is the only size measure exposed.
        XCTAssertEqual(packet.byteCount, packet.text.utf8.count)
    }
}
