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
}
