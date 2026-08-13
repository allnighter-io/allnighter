import XCTest
@testable import AllnighterCore

final class OllamaLocalRuntimeObserverTests: XCTestCase {

    private let observedAt = Date(timeIntervalSince1970: 1_754_000_000)

    // MARK: - Readiness mapping

    func testResidentModelIsBusy() {
        let transport = FixtureTransport(bodies: [
            Self.versionJSON,
            Self.tagsJSON(names: ["qwen2.5:0.5b"]),
            Self.psJSON(residents: [("qwen2.5:0.5b", 4096)]),
        ])
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .busy)
        XCTAssertEqual(snap.sourceId, "ollama_local")
        XCTAssertEqual(snap.ollamaVersion, "0.32.6")
        XCTAssertEqual(snap.residentModels.map(\.name), ["qwen2.5:0.5b"])
        XCTAssertEqual(snap.residentModels.first?.servedContextWindow, 4096)
        XCTAssertNil(snap.observeFailure)
        XCTAssertEqual(transport.requestedPaths, ["/api/version", "/api/tags", "/api/ps"])
    }

    func testReachableWithTagsAndEmptyPsIsIdle() {
        let transport = FixtureTransport(bodies: [
            Self.versionJSON,
            Self.tagsJSON(names: ["qwen2.5:0.5b", "qwen2.5-coder:7b"]),
            Self.psJSON(residents: []),
        ])
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .idle)
        XCTAssertEqual(snap.localTags.map(\.name), ["qwen2.5:0.5b", "qwen2.5-coder:7b"])
        XCTAssertTrue(snap.residentModels.isEmpty)
        XCTAssertNil(snap.observeFailure)
    }

    func testReachableWithNoTagsAndEmptyPsIsUnavailable() {
        let transport = FixtureTransport(bodies: [
            Self.versionJSON,
            Self.tagsJSON(names: []),
            Self.psJSON(residents: []),
        ])
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .unavailable)
        XCTAssertEqual(snap.ollamaVersion, "0.32.6")
        XCTAssertNil(snap.observeFailure)
    }

    func testResidentWithoutTagsIsStillBusy() {
        let transport = FixtureTransport(bodies: [
            Self.versionJSON,
            Self.tagsJSON(names: []),
            Self.psJSON(residents: [("qwen2.5:0.5b", 4096)]),
        ])
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .busy)
        XCTAssertEqual(snap.residentModels.first?.servedContextWindow, 4096)
    }

    // MARK: - Fail closed / never guess Busy

    func testTransportErrorIsUnavailableNotBusy() {
        let transport = FixtureTransport(error: URLError(.cannotConnectToHost))
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .unavailable)
        XCTAssertNotEqual(snap.readiness, .busy)
        guard case .version(.network) = snap.observeFailure else {
            XCTFail("expected version network failure, got \(String(describing: snap.observeFailure))")
            return
        }
        XCTAssertTrue(snap.residentModels.isEmpty)
        XCTAssertEqual(transport.requestedPaths, ["/api/version"])
    }

    func testTimeoutIsUnavailable() {
        let transport = FixtureTransport(error: URLError(.timedOut))
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .unavailable)
        XCTAssertEqual(snap.observeFailure, .version(.timeout))
    }

    func testHttpErrorOnVersionIsUnavailable() {
        let transport = FixtureTransport(statusByPath: [
            "/api/version": 500,
        ])
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .unavailable)
        XCTAssertEqual(snap.observeFailure, .version(.httpError(statusCode: 500)))
    }

    func testPsFailureAfterHealthyVersionAndTagsIsUnavailableNotIdle() {
        let transport = FixtureTransport(
            bodies: [
                Self.versionJSON,
                Self.tagsJSON(names: ["qwen2.5:0.5b"]),
            ],
            statusByPath: ["/api/ps": 500]
        )
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .unavailable)
        XCTAssertNotEqual(snap.readiness, .idle)
        XCTAssertNotEqual(snap.readiness, .busy)
        XCTAssertEqual(snap.localTags.map(\.name), ["qwen2.5:0.5b"])
        XCTAssertEqual(snap.observeFailure, .ps(.httpError(statusCode: 500)))
    }

    func testTagsFailureIsUnavailable() {
        let transport = FixtureTransport(
            bodies: [Self.versionJSON],
            statusByPath: ["/api/tags": 503]
        )
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .unavailable)
        XCTAssertEqual(snap.observeFailure, .tags(.httpError(statusCode: 503)))
        XCTAssertEqual(transport.requestedPaths, ["/api/version", "/api/tags"])
    }

    func testMalformedVersionJSONIsUnavailable() {
        let transport = FixtureTransport(bodies: ["not-json"])
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .unavailable)
        XCTAssertEqual(snap.observeFailure, .unparseableVersion)
    }

    func testMalformedTagsJSONIsUnavailable() {
        let transport = FixtureTransport(bodies: [Self.versionJSON, "{]"])
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .unavailable)
        XCTAssertEqual(snap.observeFailure, .unparseableTags)
    }

    func testMalformedPsJSONIsUnavailableNotBusy() {
        let transport = FixtureTransport(bodies: [
            Self.versionJSON,
            Self.tagsJSON(names: ["qwen2.5:0.5b"]),
            "[]",
        ])
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .unavailable)
        XCTAssertEqual(snap.observeFailure, .unparseablePs)
        XCTAssertTrue(snap.residentModels.isEmpty)
    }

    // MARK: - Served context vs advertised

    func testServedContextComesFromPsNotAdvertisedTagField() {
        let tags = """
        {"models":[{"name":"qwen2.5:0.5b","context_length":131072,"details":{"context_length":131072}}]}
        """
        let transport = FixtureTransport(bodies: [
            Self.versionJSON,
            tags,
            Self.psJSON(residents: [("qwen2.5:0.5b", 4096)]),
        ])
        let snap = observe(transport)
        XCTAssertEqual(snap.readiness, .busy)
        XCTAssertEqual(snap.localTags, [.init(name: "qwen2.5:0.5b")])
        XCTAssertEqual(snap.residentModels.first?.servedContextWindow, 4096)
        XCTAssertNotEqual(snap.residentModels.first?.servedContextWindow, 131072)
    }

    func testNestedDetailsContextLengthOnPsIsNotServed() {
        let ps = """
        {"models":[{"name":"qwen2.5:0.5b","details":{"context_length":131072}}]}
        """
        let parsed = OllamaLocalRuntimeObserver.parsePs(Data(ps.utf8))
        XCTAssertEqual(parsed, [.init(name: "qwen2.5:0.5b", servedContextWindow: nil)])
    }

    func testMissingPsContextLengthLeavesServedNil() {
        let ps = """
        {"models":[{"name":"qwen2.5:0.5b","size_vram":1024}]}
        """
        let parsed = OllamaLocalRuntimeObserver.parsePs(Data(ps.utf8))
        XCTAssertEqual(parsed?.first?.servedContextWindow, nil)
    }

    func testBooleanContextLengthIsNotServed() {
        let ps = """
        {"models":[{"name":"qwen2.5:0.5b","context_length":true}]}
        """
        let parsed = OllamaLocalRuntimeObserver.parsePs(Data(ps.utf8))
        XCTAssertEqual(parsed?.first?.servedContextWindow, nil)
    }

    func testParseTagsStripsAdvertisedContext() {
        let tags = """
        {"models":[{"name":"qwen2.5:0.5b","context_length":131072}]}
        """
        let parsed = OllamaLocalRuntimeObserver.parseTags(Data(tags.utf8))
        XCTAssertEqual(parsed, [.init(name: "qwen2.5:0.5b")])
    }

    // MARK: - Loopback binding

    func testRequestsOnlyLoopback11434() {
        let transport = FixtureTransport(bodies: [
            Self.versionJSON,
            Self.tagsJSON(names: ["qwen2.5:0.5b"]),
            Self.psJSON(residents: []),
        ])
        _ = observe(transport)
        XCTAssertEqual(transport.requestedURLs.count, 3)
        for url in transport.requestedURLs {
            XCTAssertEqual(url.host, "127.0.0.1")
            XCTAssertEqual(url.port, 11434)
            XCTAssertEqual(url.scheme, "http")
        }
    }

    func testModelFallbackNameFromModelField() {
        let ps = """
        {"models":[{"model":"llama3.2:3b","context_length":8192}]}
        """
        let parsed = OllamaLocalRuntimeObserver.parsePs(Data(ps.utf8))
        XCTAssertEqual(parsed, [.init(name: "llama3.2:3b", servedContextWindow: 8192)])
    }

    func testSourceIdIsOllamaLocalNotABodyName() {
        XCTAssertEqual(OllamaLocalRuntimeClient.sourceId, "ollama_local")
        let snap = OllamaLocalRuntimeObserver.snapshot(
            observedAt: observedAt,
            ollamaVersion: "0.32.6",
            localTags: [.init(name: "qwen2.5:0.5b")],
            residentModels: []
        )
        XCTAssertEqual(snap.sourceId, "ollama_local")
        XCTAssertEqual(snap.readiness, .idle)
    }

    // MARK: - Helpers

    private func observe(_ transport: FixtureTransport) -> OllamaLocalRuntimeObserver.Snapshot {
        OllamaLocalRuntimeObserver.observe(transport: transport, observedAt: observedAt)
    }

    private static let versionJSON = #"{"version":"0.32.6"}"#

    private static func tagsJSON(names: [String]) -> String {
        let models = names.map { "{\"name\":\"\($0)\"}" }.joined(separator: ",")
        return "{\"models\":[\(models)]}"
    }

    private static func psJSON(residents: [(String, Int?)]) -> String {
        let models = residents.map { name, ctx -> String in
            if let ctx {
                return "{\"name\":\"\(name)\",\"context_length\":\(ctx)}"
            }
            return "{\"name\":\"\(name)\"}"
        }.joined(separator: ",")
        return "{\"models\":[\(models)]}"
    }
}

private final class FixtureTransport: OllamaLocalRuntimeClient.Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [String]
    private let error: Error?
    private let statusByPath: [String: Int]
    private(set) var requestedURLs: [URL] = []

    var requestedPaths: [String] {
        requestedURLs.map(\.path)
    }

    init(bodies: [String] = [], error: Error? = nil, statusByPath: [String: Int] = [:]) {
        self.bodies = bodies
        self.error = error
        self.statusByPath = statusByPath
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        lock.lock()
        defer { lock.unlock() }
        let url = request.url!
        requestedURLs.append(url)
        if let error {
            throw error
        }
        let path = url.path
        let status = statusByPath[path] ?? 200
        let body: String
        if statusByPath[path] != nil {
            body = "{}"
        } else if bodies.isEmpty {
            body = "{}"
        } else {
            body = bodies.removeFirst()
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }
}
