import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class OpenCodeRoutingWorkerRunnerTests: XCTestCase {
    /// A serve coordinator wired to a fresh, unshared `SpawnState` (mirrors
    /// `OpenCodeServeCoordinatorTests`) so `ensureRunning()` never touches the
    /// process-wide `sharedState` or spawns a real process in a test.
    private func freshCoordinator(healthy: Bool = true) -> OpenCodeServeCoordinator {
        OpenCodeServeCoordinator(
            healthCheck: { healthy },
            portListenerPID: { _ in nil },
            launchServe: { throw OpenCodeServeCoordinatorError.opencodeExecutableNotFound },
            state: SpawnState()
        )
    }

    /// Fixture-backed `OpenCodeServeClient` (no live network): session create,
    /// `prompt_async` 204, and one SSE body with a text delta + `session.idle`.
    private func fixtureClient(answer: String) -> OpenCodeServeClient {
        let sessionJSON = #"{"id":"ses_route"}"#
        let sseBody = """
        data: {"type":"message.part.updated","properties":{"part":{"type":"text","text":"\(answer)"},"delta":"\(answer)"}}

        data: {"type":"session.idle","properties":{}}

        """
        let transport: OpenCodeServeClient.Transport = { req in
            let url = req.url!.absoluteString
            if url.hasSuffix("/prompt_async") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                return (Data(), resp)
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(sessionJSON.utf8), resp)
        }
        let sseTransport: OpenCodeServeClient.SSETransport = { req in
            XCTAssertTrue(req.url!.absoluteString.hasSuffix("/event"))
            return AsyncThrowingStream { continuation in
                continuation.yield(Data(sseBody.utf8))
                continuation.finish()
            }
        }
        return OpenCodeServeClient(transport: transport, sseTransport: sseTransport)
    }

    func testRoutesOpencodeManifestToServeClient() async {
        let manifest = TestSupport.headlessManifest(id: "opencode", command: "opencode")
        let worker = TestSupport.worker("w", driverId: "opencode", model: "featherless/zai-org/GLM-5.2")
        let neverCalledInner = MockWorkerInvoking.failing("the CLI path must not run for opencode")
        let routing = OpenCodeRoutingWorkerRunner(
            inner: neverCalledInner, client: fixtureClient(answer: "DONE"), coordinator: freshCoordinator())

        let result = await routing.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.status, .done)
        XCTAssertEqual(result.output, "DONE")
    }

    func testNonOpencodeManifestGoesToInner() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let inner = MockWorkerInvoking.answering(["from inner CLI path"])
        let routing = OpenCodeRoutingWorkerRunner(
            inner: inner, client: fixtureClient(answer: "unused"), coordinator: freshCoordinator())

        let result = await routing.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.status, .done)
        XCTAssertEqual(result.output, "from inner CLI path")
    }

    func testServeStartupFailureYieldsMissingCLIFailureWithoutTouchingInner() async {
        let manifest = TestSupport.headlessManifest(id: "opencode", command: "opencode")
        let worker = TestSupport.worker("w", driverId: "opencode")
        let neverCalledInner = MockWorkerInvoking.failing("the CLI path must not run for opencode")
        let routing = OpenCodeRoutingWorkerRunner(
            inner: neverCalledInner, client: fixtureClient(answer: "unused"),
            coordinator: freshCoordinator(healthy: false))

        let result = await routing.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.errorKind, .missingCLI)
    }
}
