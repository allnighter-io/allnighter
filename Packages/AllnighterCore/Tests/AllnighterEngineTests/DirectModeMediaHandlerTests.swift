import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class DirectModeMediaHandlerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_340_000)

    func testHandlerFetchesMediaWithServerTime() async throws {
        let provider = RecordingDirectModeMediaDataProvider(dataByRef: [
            "media_1": Data("ciphertext".utf8),
        ])
        let fixedNow = now
        let handler = DirectModeMediaHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            provider: provider,
            now: { fixedNow }
        )

        let response = try await handler.media(DirectModeMediaRequest(
            accountId: "acct_1",
            macAgentId: "mac_1",
            ref: "media_1",
            checkedAt: now.addingTimeInterval(-300)
        ))

        XCTAssertEqual(response, DirectModeMediaResponse(
            ref: "media_1",
            macAgentId: "mac_1",
            data: Data("ciphertext".utf8)
        ))
        let requests = await provider.requests()
        XCTAssertEqual(requests, [
            RecordingDirectModeMediaDataProvider.Request(ref: "media_1", macAgentId: "mac_1", at: now),
        ])
    }

    func testHandlerRejectsWrongAccountOrMac() async throws {
        let fixedNow = now
        let handler = DirectModeMediaHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            provider: RecordingDirectModeMediaDataProvider(dataByRef: [:]),
            now: { fixedNow }
        )

        do {
            _ = try await handler.media(DirectModeMediaRequest(
                accountId: "acct_wrong",
                macAgentId: "mac_wrong",
                ref: "media_1",
                checkedAt: now
            ))
            XCTFail("Expected request mismatch")
        } catch {
            XCTAssertEqual(
                error as? DirectModeMediaError,
                .requestMismatch(
                    expectedAccountId: "acct_1",
                    actualAccountId: "acct_wrong",
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_wrong"
                )
            )
        }
    }

    func testHandlerRejectsMissingMedia() async throws {
        let fixedNow = now
        let handler = DirectModeMediaHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            provider: RecordingDirectModeMediaDataProvider(dataByRef: [:]),
            now: { fixedNow }
        )

        do {
            _ = try await handler.media(DirectModeMediaRequest(
                accountId: "acct_1",
                macAgentId: "mac_1",
                ref: "media_missing",
                checkedAt: now
            ))
            XCTFail("Expected missing media")
        } catch {
            XCTAssertEqual(error as? DirectModeMediaError, .mediaNotFound(ref: "media_missing"))
        }
    }
}

private actor RecordingDirectModeMediaDataProvider: DirectModeMediaDataProviding {
    struct Request: Equatable {
        var ref: String
        var macAgentId: String
        var at: Date
    }

    private let dataByRef: [String: Data]
    private var storedRequests: [Request] = []

    init(dataByRef: [String: Data]) {
        self.dataByRef = dataByRef
    }

    func mediaData(ref: String, macAgentId: String, at: Date) async throws -> Data? {
        storedRequests.append(Request(ref: ref, macAgentId: macAgentId, at: at))
        return dataByRef[ref]
    }

    func requests() -> [Request] {
        storedRequests
    }
}
