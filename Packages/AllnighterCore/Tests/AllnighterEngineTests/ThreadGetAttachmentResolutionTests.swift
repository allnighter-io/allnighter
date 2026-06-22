import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

final class ThreadGetAttachmentResolutionTests: XCTestCase {
    func testThreadGetProjectionResolvesAttachmentPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("thread-get-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let store = ThreadStore(rootDirectory: root)
        try store.create(id: "t-img", title: "img", now: Date())
        let threadDir = try store.threadDirectory(forThreadId: "t-img")
        let attachmentStore = ThreadAttachmentStore(threadDirectory: threadDir)

        let ingested = try AttachmentIngestor().ingest(
            data: Self.onePixelPNG, declaredMIME: "image/png", sourceKind: AttachmentSourceKind.workerGenerated
        )
        let (_, ref) = try attachmentStore.commitIngested(
            ingested: ingested,
            attachmentId: "att-user",
            threadId: "t-img",
            sourceKind: AttachmentSourceKind.workerGenerated,
            sequence: 0,
            originalName: nil as String?,
            now: Date()
        )

        let turn = ThreadTurn(
            id: "turn-user", threadId: "t-img", kind: .userMessage, status: .done,
            createdAt: Date(), author: .user, text: "see image",
            attachmentRefs: [ref]
        )
        _ = try store.appendTurn(turn, toThreadId: "t-img", now: Date())
        let updated = try XCTUnwrap(store.get("t-img"))

        let projection = ThreadAttachmentResolver.project(
            thread: updated,
            threadDirectory: threadDir,
            contractVersion: ContractRegistry.contractVersion
        )

        XCTAssertEqual(projection.turns.count, 1)
        XCTAssertEqual(projection.turns[0].resolvedAttachments.count, 1)
        let resolved = try XCTUnwrap(projection.turns[0].resolvedAttachments.first)
        XCTAssertFalse(resolved.missing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.canonicalPath))
        XCTAssertEqual(resolved.storedSha256, ingested.storedSha256)
    }

    func testRunImagePathResolverRejectsTraversal() throws {
        let runDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        XCTAssertNil(RunImagePathResolver.absolutePath(runDirectory: runDir, relativePath: "../secret.png"))
        XCTAssertNil(RunImagePathResolver.absolutePath(runDirectory: runDir, relativePath: "/etc/passwd"))
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
}
