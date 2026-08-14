import XCTest
@testable import AllnighterCore

final class FeedbackTests: XCTestCase {
    func testCommandRegisteredInContract() {
        let spec = ContractRegistry.milestone1.commands.first { $0.name == "feedback" }
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.outputSchema, .feedbackJSON)
        XCTAssertTrue(spec?.flags.contains(where: { $0.name == "dry-run" }) == true)
        XCTAssertTrue(spec?.flags.contains(where: { $0.name == "json" }) == true)
        XCTAssertEqual(spec?.effects.humanInteraction, .never)
        XCTAssertEqual(spec?.effects.quotaSpend, .never)
        XCTAssertEqual(spec?.effects.repoWrite, .never)
    }

    func testPayloadJSONHasOnlyThreeKeys() throws {
        let payload = FeedbackPayload.make(message: "hello")
        let obj = try JSONSerialization.jsonObject(with: try CoreJSON.encode(payload)) as! [String: Any]
        XCTAssertEqual(Set(obj.keys), ["message", "binaryVersion", "os"])
        XCTAssertEqual(obj["message"] as? String, "hello")
        XCTAssertEqual(obj["binaryVersion"] as? String, AllnighterVersionIdentity.binaryVersion)
        XCTAssertTrue((obj["os"] as? String)?.hasPrefix("macOS ") == true)
    }

    func testPreviewDoesNotCallTransport() {
        let transport = StubTransport()
        let service = FeedbackService(transport: transport, rate: isolatedRate())
        let result = service.preview(message: "  hello  ")
        guard case .success(let json) = result else {
            return XCTFail("expected preview success")
        }
        XCTAssertTrue(json.dryRun)
        XCTAssertFalse(json.sent)
        XCTAssertEqual(json.payload.message, "hello")
        XCTAssertEqual(json.tellHuman, SupportHatch.feedbackDryRunTellHuman)
        XCTAssertTrue(transport.posts.isEmpty)
    }

    func testEmptyAndTooLongFailWithoutPosting() async {
        let transport = StubTransport()
        let service = FeedbackService(transport: transport, rate: isolatedRate())
        XCTAssertEqual(service.preview(message: "   ").error, .empty)
        let long = String(repeating: "a", count: FeedbackService.maxMessageLength + 1)
        XCTAssertEqual(service.preview(message: long).error, .tooLong(limit: FeedbackService.maxMessageLength))
        let sent = await service.send(message: "")
        XCTAssertEqual(sent.error, .empty)
        XCTAssertTrue(transport.posts.isEmpty)
    }

    func testSendSuccessConsumesRateAndPrintsSentHatch() async {
        let transport = StubTransport()
        let rate = isolatedRate()
        let service = FeedbackService(transport: transport, rate: rate)
        let result = await service.send(message: "Spec Review was great")
        guard case .success(let json) = result else {
            return XCTFail("expected send success, got \(result)")
        }
        XCTAssertTrue(json.sent)
        XCTAssertFalse(json.dryRun)
        XCTAssertEqual(json.tellHuman, SupportHatch.feedbackSentTellHuman)
        XCTAssertEqual(transport.posts.count, 1)
        XCTAssertEqual(rate.remaining(), FeedbackRateStore.dailyLimit - 1)
    }

    func testUnavailableDoesNotConsumeRate() async {
        let transport = StubTransport()
        transport.status = 503
        transport.body = Data(#"{"message":"inbox is not configured"}"#.utf8)
        let rate = isolatedRate()
        let service = FeedbackService(transport: transport, rate: rate)
        let result = await service.send(message: "hello")
        XCTAssertEqual(result.error, .unavailable(detail: #"{"message":"inbox is not configured"}"#))
        XCTAssertEqual(rate.remaining(), FeedbackRateStore.dailyLimit)
    }

    func testRejectedDoesNotConsumeRate() async {
        let transport = StubTransport()
        transport.status = 400
        transport.body = Data(#"{"message":"invalid json"}"#.utf8)
        let rate = isolatedRate()
        let service = FeedbackService(transport: transport, rate: rate)
        let result = await service.send(message: "hello")
        XCTAssertEqual(result.error, .rejected(detail: #"{"message":"invalid json"}"#))
        XCTAssertEqual(rate.remaining(), FeedbackRateStore.dailyLimit)
    }

    func testDailyLimitIsFive() async {
        let transport = StubTransport()
        let rate = isolatedRate()
        let service = FeedbackService(transport: transport, rate: rate)
        for i in 1...5 {
            let result = await service.send(message: "note \(i)")
            guard case .success = result else {
                return XCTFail("expected success on \(i), got \(result)")
            }
        }
        let sixth = await service.send(message: "one more")
        XCTAssertEqual(sixth.error, .rateLimited(limit: 5))
        XCTAssertEqual(transport.posts.count, 5)
    }

    func testRateStoreResetsOnNextUTCDay() {
        final class Clock: @unchecked Sendable {
            var now = Date(timeIntervalSince1970: 1_724_000_000)
        }
        let clock = Clock()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rate = FeedbackRateStore(directory: dir, clock: { clock.now })
        XCTAssertTrue(rate.consume())
        XCTAssertEqual(rate.remaining(), 4)
        clock.now = clock.now.addingTimeInterval(86_400)
        XCTAssertEqual(rate.remaining(), 5)
    }

    private func isolatedRate() -> FeedbackRateStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-rate-\(UUID().uuidString)")
        return FeedbackRateStore(directory: dir)
    }
}

private final class StubTransport: FeedbackTransporting, @unchecked Sendable {
    var status: Int = 200
    var body: Data = Data(#"{"ok":true}"#.utf8)
    var posts: [FeedbackPayload] = []
    func post(_ payload: FeedbackPayload) async throws -> (status: Int, body: Data) {
        posts.append(payload)
        return (status, body)
    }
}

private extension Result where Failure == FeedbackError {
    var error: FeedbackError? {
        switch self {
        case .failure(let error): return error
        case .success: return nil
        }
    }
}
