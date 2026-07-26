import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class AttachmentDeliveryRendererTests: XCTestCase {
    func testPathBlockSortedBySequence() {
        let block = AttachmentDeliveryRenderer.pathBlock(deliveries: [
            IncludedAttachmentDelivery(
                attachmentId: "b", sequence: 1,
                canonicalPath: "/c/b.png", deliveredPathUsed: "b.png", storedSha256: "bb"
            ),
            IncludedAttachmentDelivery(
                attachmentId: "a", sequence: 0,
                canonicalPath: "/c/a.png", deliveredPathUsed: "a.png", storedSha256: "aa"
            ),
        ])
        XCTAssertTrue(block.contains("1. a.png"))
        XCTAssertTrue(block.range(of: "1. a.png")!.upperBound < block.range(of: "2. b.png")!.lowerBound)
    }

    func testProtectedPromptFailsWhenCapExceeded() {
        XCTAssertThrowsError(try AttachmentDeliveryRenderer.protectedPrompt(
            baseText: String(repeating: "x", count: 1000),
            deliveries: [
                IncludedAttachmentDelivery(
                    attachmentId: "a", sequence: 0,
                    canonicalPath: "/c/a.png", deliveredPathUsed: "a.png", storedSha256: "aa"
                )
            ],
            readsImages: true,
            byteCap: 100
        )) { error in
            XCTAssertEqual(error as? AttachmentError, .contextCapExceeded)
        }
    }
}

final class ThreadSendCoordinatorAttachmentTests: XCTestCase {
    private let clock = Date(timeIntervalSince1970: 1_700_000_000)

    private func tinyPNGFile(in dir: URL) throws -> URL {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 4, height: 4,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = context.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        _ = CGImageDestinationFinalize(dest)
        let url = dir.appendingPathComponent("input.png")
        try (data as Data).write(to: url)
        return url
    }

    func testFakeVisionWorkerReceivesPathAndHashMatches() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("send-\(UUID().uuidString)")
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let threads = root.appendingPathComponent("threads")
        let store = ThreadStore(rootDirectory: threads)
        try store.create(id: "t1", title: "img", now: clock, workingDir: repo.path, defaultWorkerId: "vision")

        let png = try tinyPNGFile(in: root)
        let ingested = try AttachmentIngestor().ingest(fileURL: png, sourceKind: .cliFile)
        let frozen = root.appendingPathComponent("frozen.png")
        try ingested.pngData.write(to: frozen)

        let capture = PromptCapturingCommandRunner()
        let worker = TestSupport.worker("vision", driverId: "fake_vision")
        let manifest = TestSupport.visionManifest(id: "fake_vision", command: "fake-vision")
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
                message: "what color?",
                images: [ThreadSendCoordinator.ImageInput(frozenFileURL: frozen, sourceKind: .cliFile)]
            ),
            toThreadId: "t1"
        )

        let prompt = try XCTUnwrap(capture.lastPrompt())
        let delivery = try XCTUnwrap(result.deliveries.first)
        XCTAssertTrue(prompt.contains(delivery.deliveredPathUsed))
        XCTAssertTrue(prompt.contains(delivery.storedSha256))

        let packet = try XCTUnwrap(store.packet(threadId: "t1", packetId: result.contextPacketId))
        XCTAssertEqual(packet.includedAttachments, result.deliveries)
    }

    func testImageOnlySendAllowed() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("send2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThreadStore(rootDirectory: root.appendingPathComponent("threads"))
        try store.create(id: "t1", title: "img", now: clock, defaultWorkerId: "vision")

        let png = try tinyPNGFile(in: root)
        let frozen = root.appendingPathComponent("frozen.png")
        try Data(contentsOf: png).write(to: frozen)

        let capture = PromptCapturingCommandRunner()
        let worker = TestSupport.worker("vision", driverId: "fake_vision")
        let manifest = TestSupport.visionManifest(id: "fake_vision", command: "fake-vision")
        let fixedClock = clock
        let coordinator = ThreadSendCoordinator(
            store: store,
            commandRunner: capture,
            registry: DriverRegistry([manifest]),
            models: [worker],
            idFactory: { UUID().uuidString },
            now: { fixedClock }
        )

        let result = try await coordinator.send(
            request: ThreadSendCoordinator.Request(
                message: "",
                images: [ThreadSendCoordinator.ImageInput(frozenFileURL: frozen, sourceKind: .cliFile)]
            ),
            toThreadId: "t1"
        )
        XCTAssertEqual(result.attachmentIds.count, 1)
        XCTAssertEqual(store.get("t1")?.turns.first?.attachmentRefs.count, 1)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func next() -> String { lock.lock(); defer { lock.unlock() }; n += 1; return "id\(n)" }
    }

    private struct ImageWritingRunner: CommandRunner {
        func run(
            command: String, args: [String], stdin: String?, env: [String: String],
            workingDirectory: String?, timeout: Duration
        ) async -> CommandResult {
            let blob = stdin ?? args.joined(separator: " ")
            let patterns = [#"Save to (\S+)"#, #"Save the final image to (\S+)"#]
            for pattern in patterns {
                if let path = WorkerImageCapture.firstCapture(blob, pattern: pattern) {
                    if let png = try? Self.validPNGData() {
                        try? png.write(to: URL(fileURLWithPath: path))
                    }
                    break
                }
            }
            return CommandResult(stdout: "Here is your cute cat photo.", exitCode: 0)
        }

        private static func validPNGData() throws -> Data {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(
                data: nil, width: 4, height: 4,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            let image = context.makeImage()!
            let data = NSMutableData()
            let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            _ = CGImageDestinationFinalize(dest)
            return data as Data
        }
    }

    private func fakeImageManifest() -> DriverManifest {
        DriverManifest(
            id: "fake_image", displayName: "Fake Image", kind: .headlessCLI,
            invoke: .init(command: "fake-image", args: ["-p", "{{prompt}}"]),
            imageGen: .init(
                args: ["-p", "{{prompt}}"],
                promptTemplate: "Generate: {{designPrompt}} Save to {{imageOut}}",
                arrival: .promptDirected
            )
        )
    }

    func testWorkerImageCaptureCommitsAttachmentOnCompleteSend() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wio-send-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThreadStore(rootDirectory: root.appendingPathComponent("threads"))
        try store.create(id: "t1", title: "cat", now: clock, defaultWorkerId: "img")

        let runner = ImageWritingRunner()
        let worker = TestSupport.worker("img", driverId: "fake_image")
        let counter = Counter()
        let fixedClock = clock
        let coordinator = ThreadSendCoordinator(
            store: store,
            commandRunner: runner,
            registry: DriverRegistry([fakeImageManifest()]),
            models: [worker],
            idFactory: { counter.next() },
            now: { fixedClock }
        )

        let result = try await coordinator.send(
            request: ThreadSendCoordinator.Request(message: "generate an image of a cute cat"),
            toThreadId: "t1"
        )

        XCTAssertEqual(result.workerAttachmentIds.count, 1)
        XCTAssertEqual(result.attachmentIds, [])
        let thread = try XCTUnwrap(store.get("t1"))
        let workerTurn = try XCTUnwrap(thread.turns.last { $0.kind == .workerChat })
        XCTAssertEqual(workerTurn.attachmentRefs.count, 1)
        XCTAssertEqual(workerTurn.attachmentRefs[0].sequence, 0)

        let threadDir = try store.threadDirectory(forThreadId: "t1")
        let attachmentPath = threadDir
            .appendingPathComponent("attachments/\(result.workerAttachmentIds[0]).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentPath.path))
    }

    func testDesignBoardPickMaterializedIntoContextPacket() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wio-board-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let runsRoot = root.appendingPathComponent("runs")
        let runStore = RunStore(rootDirectory: runsRoot)
        let store = ThreadStore(rootDirectory: root.appendingPathComponent("threads"))
        try store.create(id: "t1", title: "design", now: clock, defaultWorkerId: "img")

        let runId = "run-design-1"
        let runDir = try runStore.runDirectory(forRunId: runId)
        let optionPath = "option_a.png"
        let png = try tinyPNGFile(in: runDir.deletingLastPathComponent())
        try FileManager.default.copyItem(at: png, to: runDir.appendingPathComponent(optionPath))

        var run = TeamRun(
            id: runId, prompt: "improve", status: .complete,
            workers: [TestSupport.seat("img")],
            createdAt: clock
        )
        run.stages = [
            StageOutput(
                id: "board1", purpose: .board, status: .done,
                payload: .board(BoardPayload(
                    targetShape: .mobile,
                    options: [
                        DesignOption(
                            workerId: "img#0", modelId: "img", persona: "bold",
                            imagePath: optionPath, status: .done
                        )
                    ],
                    chosen: ChosenOption(workerId: "img#0", persona: "bold")
                )),
                startedAt: clock, finishedAt: clock
            )
        ]
        try runStore.save(run, models: [TestSupport.worker("img", driverId: "fake_image")])

        let boardTurn = ThreadTurn(
            id: "board-turn", threadId: "t1", kind: .designBoard, status: .done,
            createdAt: clock, completedAt: clock, author: .system, runId: runId
        )
        _ = try store.appendTurn(boardTurn, toThreadId: "t1", now: clock)

        let runner = ImageWritingRunner()
        let worker = TestSupport.worker("img", driverId: "fake_image")
        let counter = Counter()
        let fixedClock = clock
        let coordinator = ThreadSendCoordinator(
            store: store,
            commandRunner: runner,
            registry: DriverRegistry([fakeImageManifest()]),
            models: [worker],
            seedResolver: ThreadImageSeedResolver(runStore: runStore),
            idFactory: { counter.next() },
            now: { fixedClock }
        )

        let result = try await coordinator.send(
            request: ThreadSendCoordinator.Request(message: "make the header bolder"),
            toThreadId: "t1"
        )

        let thread = try XCTUnwrap(store.get("t1"))
        XCTAssertTrue(thread.turns.contains { $0.kind == .userDecision })
        let packet = try XCTUnwrap(store.packet(threadId: "t1", packetId: result.contextPacketId))
        XCTAssertEqual(packet.includedAttachments.count, 1)
        XCTAssertTrue(packet.includedAttachments[0].canonicalPath.contains("attachments/"))
    }

    func testIdempotencyReplayReturnsWorkerAttachmentIdsForNewRecords() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wio-idem-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("idem.json")
        let store = ThreadSendIdempotencyStore(fileURL: file)
        let payload = ThreadSendCanonicalPayload(threadId: "t1", message: "generate an image", workerId: "img", imageHashes: [])
        let entry = try store.record(
            key: "k1", payload: payload, userTurnId: "u1", workerTurnId: "w1",
            workerAttachmentIds: ["att-worker-1"]
        )
        switch store.lookup(key: "k1", payload: payload) {
        case .hit(let hit):
            XCTAssertEqual(hit.workerAttachmentIds, entry.workerAttachmentIds)
        default:
            XCTFail("expected idempotency hit")
        }
    }
}

final class WorkspaceAttachmentStagingTests: XCTestCase {
    func testStagesMirrorAndGitignore() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stage-\(UUID().uuidString)")
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "node_modules/\n".write(to: repo.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let canonical = root.appendingPathComponent("canon.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: canonical) // stub bytes for copy test won't work - use real tiny png from helper

        // use minimal valid approach - copy empty file is enough for staging path test
        let attachment = TurnAttachment(
            id: "a1", threadId: "t1", createdAt: Date(), storagePath: "attachments/a1.png",
            mimeType: "image/png", byteSize: 4, storedSha256: "x", sourceKind: .cliFile, wasDownscaled: false
        )
        try Data([1, 2, 3, 4]).write(to: canonical)

        var deliveries = [
            IncludedAttachmentDelivery(
                attachmentId: "a1", sequence: 0,
                canonicalPath: canonical.path, deliveredPathUsed: canonical.path, storedSha256: "x"
            )
        ]
        let warnings = try WorkspaceAttachmentStaging.stage(
            attachments: [attachment],
            deliveries: &deliveries,
            threadId: "t1",
            workingDir: repo.path,
            canonicalURL: { _ in canonical }
        )
        XCTAssertTrue(warnings.isEmpty)
        XCTAssertTrue(deliveries[0].deliveredPathUsed.hasPrefix(".allnighter/attachments/thread_t1/"))
        let ignore = try String(contentsOf: repo.appendingPathComponent(".gitignore"))
        XCTAssertTrue(ignore.contains(".allnighter/"))
    }
}
