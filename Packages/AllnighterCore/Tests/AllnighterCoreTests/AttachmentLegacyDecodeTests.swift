import XCTest
@testable import AllnighterCore

/// Law §10: legacy thread fixtures decode with empty attachment arrays.
final class AttachmentLegacyDecodeTests: XCTestCase {

    func testLegacyThreadChatFixtureDecodesEmptyAttachmentRefs() throws {
        let thread = try Fixtures.decode(WorkThread.self, .threadChat)
        XCTAssertFalse(thread.turns.isEmpty)
        for turn in thread.turns {
            XCTAssertEqual(turn.attachmentRefs, [])
            XCTAssertEqual(turn.fileReferenceRefs, [])
        }
    }

    func testLegacyContextPacketDecodesEmptyIncludedAttachments() throws {
        let packet = try Fixtures.decode(ThreadContextPacket.self, .threadContextPacket)
        XCTAssertEqual(packet.includedAttachments, [])
        XCTAssertEqual(packet.includedFileReferences, [])
    }

    func testContextPacketRoundTripWithIncludedAttachments() throws {
        let packet = ThreadContextPacket(
            id: "p1", threadId: "th1", turnId: "t1", createdAt: Date(timeIntervalSince1970: 0),
            strategy: .recentTurns, text: "body",
            includedAttachments: [
                IncludedAttachmentDelivery(
                    attachmentId: "a1", sequence: 0,
                    canonicalPath: "/canon/a1.png", deliveredPathUsed: ".allnighter/a1.png",
                    storedSha256: "abc"
                )
            ]
        )
        let data = try CoreJSON.encode(packet)
        let decoded = try CoreJSON.decode(ThreadContextPacket.self, from: data)
        XCTAssertEqual(decoded.includedAttachments, packet.includedAttachments)
    }

    func testContextPacketRoundTripWithIncludedFileReferences() throws {
        let packet = ThreadContextPacket(
            id: "p1", threadId: "th1", turnId: "t1", createdAt: Date(timeIntervalSince1970: 0),
            strategy: .recentTurns, includedFiles: ["Sources/App.swift"], text: "body",
            includedFileReferences: [
                IncludedFileReferenceDelivery(
                    referenceId: "f1",
                    sequence: 0,
                    projectId: "proj1",
                    rootRelativePath: "Sources/App.swift",
                    lineRange: FileLineRange(startLine: 2, endLine: 4),
                    resolvedAbsolutePath: "/repo/Sources/App.swift",
                    deliveredPathUsed: "Sources/App.swift",
                    storedSha256: "abc",
                    byteSize: 100,
                    deliveredByteCount: 40,
                    truncated: false,
                    languageHint: "swift",
                    deliveryMode: .attachedFileBlock
                )
            ]
        )
        let data = try CoreJSON.encode(packet)
        let decoded = try CoreJSON.decode(ThreadContextPacket.self, from: data)
        XCTAssertEqual(decoded.includedFileReferences, packet.includedFileReferences)
    }

    func testWorkerGeneratedSourceKindRoundTrips() throws {
        let attachment = TurnAttachment(
            id: "w1", threadId: "th1", createdAt: Date(timeIntervalSince1970: 0),
            storagePath: "attachments/w1.png", mimeType: "image/png", byteSize: 10,
            storedSha256: "abc", sourceKind: .workerGenerated, wasDownscaled: false
        )
        let data = try CoreJSON.encode(attachment)
        let decoded = try CoreJSON.decode(TurnAttachment.self, from: data)
        XCTAssertEqual(decoded.sourceKind, .workerGenerated)
    }

    func testThreadTurnRoundTripWithAttachments() throws {
        let turn = ThreadTurn(
            id: "t1", threadId: "th1", kind: .userMessage, status: .done,
            createdAt: Date(timeIntervalSince1970: 0), author: .user, text: "hi",
            attachmentRefs: [TurnAttachmentRef(attachmentId: "a1", sequence: 0)],
            fileReferenceRefs: [TurnFileReferenceRef(referenceId: "f1", sequence: 0)]
        )
        let data = try CoreJSON.encode(turn)
        let decoded = try CoreJSON.decode(ThreadTurn.self, from: data)
        XCTAssertEqual(decoded.attachmentRefs, turn.attachmentRefs)
        XCTAssertEqual(decoded.fileReferenceRefs, turn.fileReferenceRefs)
    }
}
