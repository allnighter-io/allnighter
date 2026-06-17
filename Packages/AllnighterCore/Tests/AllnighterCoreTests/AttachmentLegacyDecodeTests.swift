import XCTest
@testable import AllnighterCore

/// Law §10: legacy thread fixtures decode with empty attachment arrays.
final class AttachmentLegacyDecodeTests: XCTestCase {

    func testLegacyThreadChatFixtureDecodesEmptyAttachmentRefs() throws {
        let thread = try Fixtures.decode(WorkThread.self, .threadChat)
        XCTAssertFalse(thread.turns.isEmpty)
        for turn in thread.turns {
            XCTAssertEqual(turn.attachmentRefs, [])
        }
    }

    func testLegacyContextPacketDecodesEmptyIncludedAttachments() throws {
        let packet = try Fixtures.decode(ThreadContextPacket.self, .threadContextPacket)
        XCTAssertEqual(packet.includedAttachments, [])
    }

    func testThreadTurnRoundTripWithAttachments() throws {
        let turn = ThreadTurn(
            id: "t1", threadId: "th1", kind: .userMessage, status: .done,
            createdAt: Date(timeIntervalSince1970: 0), author: .user, text: "hi",
            attachmentRefs: [TurnAttachmentRef(attachmentId: "a1", sequence: 0)]
        )
        let data = try CoreJSON.encode(turn)
        let decoded = try CoreJSON.decode(ThreadTurn.self, from: data)
        XCTAssertEqual(decoded.attachmentRefs, turn.attachmentRefs)
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
}
