import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

final class ThreadSendFileReferenceTests: XCTestCase {
    private let clock = Date(timeIntervalSince1970: 1_700_000_000)

    func testFakeWorkerReceivesReferencedFileTextAndTurnRefs() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("send-file-ref-\(UUID().uuidString)", isDirectory: true)
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "struct App {}\nlet answer = 42\n".write(
            to: repo.appendingPathComponent("Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )

        let store = ThreadStore(rootDirectory: root.appendingPathComponent("threads"))
        try store.create(id: "t1", title: "code", now: clock, workingDir: repo.path, defaultWorkerId: "code")

        let capture = PromptCapturingCommandRunner()
        let worker = TestSupport.worker("code", driverId: "fake_code")
        let manifest = TestSupport.headlessManifest(id: "fake_code", command: "fake-code")
        let counter = Counter()
        let fixedClock = clock
        let coordinator = ThreadSendCoordinator(
            store: store,
            commandRunner: capture,
            registry: DriverRegistry([manifest]),
            models: [worker],
            idFactory: { counter.next() },
            now: { fixedClock }
        )

        let result = try await coordinator.send(
            request: ThreadSendCoordinator.Request(
                message: "read this",
                fileReferences: [
                    FileReferenceInput(
                        path: "Sources/App.swift",
                        lineRange: FileLineRange(startLine: 2, endLine: 2)
                    )
                ]
            ),
            toThreadId: "t1"
        )

        let prompt = try XCTUnwrap(capture.lastPrompt())
        XCTAssertTrue(prompt.contains("Referenced files:"))
        XCTAssertTrue(prompt.contains("Sources/App.swift (lines 2-2, swift):\nlet answer = 42"))
        XCTAssertFalse(prompt.contains("struct App {}"))
        XCTAssertEqual(result.fileReferenceIds.count, 1)
        XCTAssertEqual(result.fileReferences.count, 1)
        XCTAssertEqual(result.fileReferences[0].rootRelativePath, "Sources/App.swift")

        let thread = try XCTUnwrap(store.get("t1"))
        let userTurn = try XCTUnwrap(thread.turns.first { $0.kind == .userMessage })
        XCTAssertEqual(userTurn.fileReferenceRefs, [TurnFileReferenceRef(referenceId: result.fileReferenceIds[0], sequence: 0)])

        let packet = try XCTUnwrap(store.packet(threadId: "t1", packetId: result.contextPacketId))
        XCTAssertEqual(packet.includedFileReferences, result.fileReferences)
        XCTAssertEqual(packet.includedFiles, ["Sources/App.swift"])
    }

    func testMessageAtTokenIsResolvedAsFileReference() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("send-at-ref-\(UUID().uuidString)", isDirectory: true)
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "hello from readme\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let store = ThreadStore(rootDirectory: root.appendingPathComponent("threads"))
        try store.create(id: "t1", title: "docs", now: clock, workingDir: repo.path, defaultWorkerId: "code")

        let capture = PromptCapturingCommandRunner()
        let worker = TestSupport.worker("code", driverId: "fake_code")
        let manifest = TestSupport.headlessManifest(id: "fake_code", command: "fake-code")
        let fixedClock = clock
        let coordinator = ThreadSendCoordinator(
            store: store,
            commandRunner: capture,
            registry: DriverRegistry([manifest]),
            models: [worker],
            now: { fixedClock }
        )

        let result = try await coordinator.send(
            request: ThreadSendCoordinator.Request(message: "please read @README.md"),
            toThreadId: "t1"
        )

        XCTAssertTrue(try XCTUnwrap(capture.lastPrompt()).contains("hello from readme"))
        XCTAssertEqual(result.fileReferences.first?.rootRelativePath, "README.md")
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func next() -> String {
            lock.lock()
            defer { lock.unlock() }
            n += 1
            return "id\(n)"
        }
    }
}
