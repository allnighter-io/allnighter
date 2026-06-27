import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Fixture-backed proof of the OpenCode HTTP answer channel — no live network.
/// Bodies are frozen from a real capture (opencode 1.17.11, Featherless):
///   POST /session                -> {"id":"ses_…"}
///   POST /session/{id}/message   -> {"info":{…},"parts":[step-start, text, step-finish]}
/// Satisfies the regression law: OpenCode readiness must be fixture-proven, never
/// inferred from `opencode run` stdout.
final class OpenCodeServeClientTests: XCTestCase {
    func testSplitModelLabelSplitsOnFirstSlashOnly() {
        let s = OpenCodeServeClient.splitModelLabel("featherless/zai-org/GLM-5.2")
        XCTAssertEqual(s.providerID, "featherless")
        XCTAssertEqual(s.modelID, "zai-org/GLM-5.2")
    }

    func testPromptCreatesSessionSendsCorrectBodyAndExtractsTextPart() async throws {
        let sessionJSON = #"{"id":"ses_test123"}"#
        // step-start / step-finish parts MUST be ignored; only the text part is the answer.
        let messageJSON = #"{"info":{"role":"assistant","modelID":"zai-org/GLM-5.2"},"parts":[{"type":"step-start","id":"p1"},{"type":"text","text":"ALLNIGHTER_READY"},{"type":"step-finish","id":"p3","reason":"stop"}]}"#

        let transport: OpenCodeServeClient.Transport = { req in
            let url = req.url!.absoluteString
            if url.hasSuffix("/message") {
                // Verify the request contract: model split + text part.
                let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as! [String: Any]
                let model = body["model"] as! [String: Any]
                XCTAssertEqual(model["providerID"] as? String, "featherless")
                XCTAssertEqual(model["modelID"] as? String, "zai-org/GLM-5.2")
                let parts = body["parts"] as! [[String: Any]]
                XCTAssertEqual(parts.first?["type"] as? String, "text")
                XCTAssertEqual(parts.first?["text"] as? String, "Reply with the single token ALLNIGHTER_READY")
            }
            let body = url.hasSuffix("/message") ? messageJSON : sessionJSON
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), resp)
        }

        let client = OpenCodeServeClient(
            baseURL: URL(string: "http://127.0.0.1:4096")!,
            transport: transport
        )
        let answer = try await client.prompt(
            "Reply with the single token ALLNIGHTER_READY",
            modelLabel: "featherless/zai-org/GLM-5.2"
        )
        XCTAssertEqual(answer, "ALLNIGHTER_READY")
    }

    func testNoTextPartsThrowsEmptyAnswer() async {
        let transport: OpenCodeServeClient.Transport = { req in
            let url = req.url!.absoluteString
            let body = url.hasSuffix("/message")
                ? #"{"parts":[{"type":"step-start"},{"type":"step-finish"}]}"#
                : #"{"id":"ses_x"}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), resp)
        }
        let client = OpenCodeServeClient(transport: transport)
        do {
            _ = try await client.prompt("hi", modelLabel: "featherless/Qwen/Qwen3-Coder-Next")
            XCTFail("expected emptyAnswer to throw")
        } catch let error as OpenCodeServeClient.ClientError {
            XCTAssertEqual(error, .emptyAnswer)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testHTTPErrorSurfacesReason() async {
        let transport: OpenCodeServeClient.Transport = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"error":"boom"}"#.utf8), resp)
        }
        let client = OpenCodeServeClient(transport: transport)
        do {
            _ = try await client.prompt("hi", modelLabel: "featherless/Qwen/Qwen3-Coder-Next")
            XCTFail("expected sessionCreateFailed to throw")
        } catch let error as OpenCodeServeClient.ClientError {
            guard case .sessionCreateFailed = error else { return XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRunRootsSessionInDirectoryAutoApprovesAndCapturesReasoning() async throws {
        let sessionJSON = #"{"id":"ses_dir"}"#
        // reasoning part (thinking) must be captured separately from the answer text part.
        let messageJSON = #"{"parts":[{"type":"step-start"},{"type":"reasoning","text":"thinking hard"},{"type":"text","text":"DONE"},{"type":"step-finish"}]}"#
        let transport: OpenCodeServeClient.Transport = { req in
            let url = req.url!
            if url.absoluteString.contains("/message") {
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(messageJSON.utf8), resp)
            }
            // session create: assert the working dir + allow-all permission contract.
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(comps.queryItems?.first(where: { $0.name == "directory" })?.value, "/repo/root")
            let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as! [String: Any]
            let perm = body["permission"] as! [[String: Any]]
            XCTAssertEqual(perm.first?["action"] as? String, "allow")
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(sessionJSON.utf8), resp)
        }
        let client = OpenCodeServeClient(transport: transport)
        let answer = try await client.run(
            "do it", modelLabel: "featherless/zai-org/GLM-5.2",
            directory: "/repo/root", autoApprove: true
        )
        XCTAssertEqual(answer.text, "DONE")
        XCTAssertEqual(answer.reasoning, "thinking hard")
    }

    func testStreamRunFixtureYieldsDeltasAndTerminal() async throws {
        let sessionJSON = #"{"id":"ses_stream"}"#
        let sseBody = """
        data: {"type":"message.part.updated","properties":{"part":{"type":"text","text":"READY"},"delta":"READY"}}

        data: {"type":"session.idle","properties":{}}

        """
        let transport: OpenCodeServeClient.Transport = { req in
            let url = req.url!.absoluteString
            if url.hasSuffix("/prompt_async") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                return (Data(), resp)
            }
            if url.hasSuffix("/event") {
                XCTFail("SSE should use sseTransport, not transport")
            }
            let body = sessionJSON
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), resp)
        }
        let sseTransport: OpenCodeServeClient.SSETransport = { req in
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/event"))
            return AsyncThrowingStream { continuation in
                continuation.yield(Data(sseBody.utf8))
                continuation.finish()
            }
        }
        let client = OpenCodeServeClient(transport: transport, sseTransport: sseTransport)
        var deltas: [String] = []
        var terminal: WorkerRunOutcome?
        for try await event in client.streamRun(
            "Reply READY", modelLabel: "featherless/zai-org/GLM-5.2",
            autoApprove: true, timeout: .seconds(5)
        ) {
            switch event {
            case .answerDelta(let text, _, _): deltas.append(text)
            case .completed(let o): terminal = o
            case .failed(let o): terminal = o
            default: break
            }
        }
        XCTAssertEqual(deltas.joined(), "READY")
        XCTAssertEqual(terminal?.status, .done)
        XCTAssertEqual(terminal?.output, "READY")
    }

    /// The control-plane bug this fixes: a review/execute turn where the model does its work
    /// entirely through tools (writes the findings file) and reaches `session.idle` with NO
    /// closing assistant text. Old behavior marked this `empty_output`/failed; it must now be
    /// a tool-only *success* so the check-passing deliverable isn't reported as a failure.
    func testStreamRunToolOnlyCompletionIsDone() async throws {
        let sseBody = """
        data: {"type":"message.part.updated","properties":{"part":{"type":"tool","callID":"call_1","tool":"write","state":{"status":"completed"}}}}

        data: {"type":"session.idle","properties":{}}

        """
        let terminal = try await runFixtureStream(sseBody)
        XCTAssertEqual(terminal?.status, .done)
        XCTAssertNil(terminal?.errorKind)
        XCTAssertEqual(terminal?.output?.contains("1 tool action"), true)
    }

    /// A genuinely empty turn — no text, no tool work — stays a failure.
    func testStreamRunNoTextNoToolsIsEmptyOutputFailure() async throws {
        let sseBody = """
        data: {"type":"session.idle","properties":{}}

        """
        let terminal = try await runFixtureStream(sseBody)
        XCTAssertEqual(terminal?.status, .failed)
        XCTAssertEqual(terminal?.errorKind, .emptyOutput)
    }

    /// A reported `session.error` is a failure even if a tool ran first.
    func testStreamRunSessionErrorIsFailure() async throws {
        let sseBody = """
        data: {"type":"message.part.updated","properties":{"part":{"type":"tool","callID":"call_1","tool":"bash","state":{"status":"running"}}}}

        data: {"type":"session.error","properties":{"error":{"name":"UnknownError","data":{"message":"boom"}}}}

        """
        let terminal = try await runFixtureStream(sseBody)
        XCTAssertEqual(terminal?.status, .failed)
        XCTAssertEqual(terminal?.errorKind, .nonzeroExit)
        XCTAssertEqual(terminal?.errorReason?.contains("boom"), true)
    }

    /// Drive `streamRun` over a canned SSE body and return its terminal outcome.
    private func runFixtureStream(_ sseBody: String) async throws -> WorkerRunOutcome? {
        let sessionJSON = #"{"id":"ses_stream"}"#
        let transport: OpenCodeServeClient.Transport = { req in
            let url = req.url!.absoluteString
            if url.hasSuffix("/prompt_async") {
                return (Data(), HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!)
            }
            return (Data(sessionJSON.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let sseTransport: OpenCodeServeClient.SSETransport = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(Data(sseBody.utf8))
                continuation.finish()
            }
        }
        let client = OpenCodeServeClient(transport: transport, sseTransport: sseTransport)
        var terminal: WorkerRunOutcome?
        for try await event in client.streamRun(
            "do it", modelLabel: "featherless/zai-org/GLM-5.2",
            autoApprove: true, timeout: .seconds(5)
        ) {
            switch event {
            case .completed(let o), .failed(let o): terminal = o
            default: break
            }
        }
        return terminal
    }
}
