import XCTest
@testable import AllnighterCore

/// OCL-S03 — pulled Ollama tags become discovered candidate seats.
/// Tests never open a socket to a live Ollama.
final class OllamaLocalModelDiscoveryProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_754_000_000)

    func testLocalTagsBecomeDiscoveredCandidatesEnabledNone() {
        let snapshot = idleSnapshot(tags: ["gpt-oss:20b", "qwen2.5:0.5b"])
        let result = OllamaLocalModelDiscoveryProvider.result(from: snapshot, discoveredAt: now)
        XCTAssertEqual(result.driverId, "ollama_local")
        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertTrue(result.diagnostics.isEmpty)
        XCTAssertEqual(result.discoveredAt, now)

        let first = result.candidates[0]
        XCTAssertEqual(first.origin, .discovered)
        XCTAssertFalse(first.defaultEnabled)
        XCTAssertEqual(first.driverId, "ollama_local")
        XCTAssertEqual(first.modelLabel, "ollama/gpt-oss:20b")
        XCTAssertEqual(first.displayName, "gpt-oss:20b")
        XCTAssertEqual(first.id, "discovered_ollama_gpt_oss_20b")
        XCTAssertTrue(OllamaLocalDoctorReport.isOllamaBackedSeat(modelLabel: first.modelLabel))
        XCTAssertTrue(first.capabilities.capabilityTags.isEmpty)
        XCTAssertEqual(first.capabilities.strengthRank, 0)

        XCTAssertFalse(result.candidates.contains { $0.driverId == "claude_code" })
        XCTAssertFalse(result.candidates.contains { $0.driverId == "opencode" })
        XCTAssertTrue(result.candidates.allSatisfy { !$0.defaultEnabled })
        XCTAssertTrue(result.candidates.allSatisfy { $0.origin == .discovered })
    }

    func testCloudTagsDroppedByObserverNeverBecomeCandidates() {
        let tagsJSON = """
        {"models":[
          {"name":"gpt-oss:20b"},
          {"name":"cloud-one","remote_host":"ollama.com"}
        ]}
        """
        let tags = OllamaLocalRuntimeObserver.parseTags(Data(tagsJSON.utf8))!
        let snapshot = OllamaLocalRuntimeObserver.snapshot(
            observedAt: now,
            ollamaVersion: "0.32.6",
            localTags: tags,
            residentModels: []
        )
        let result = OllamaLocalModelDiscoveryProvider.result(from: snapshot, discoveredAt: now)
        XCTAssertEqual(result.candidates.map(\.displayName), ["gpt-oss:20b"])
    }

    func testUnreachableYieldsNoCandidates() {
        let snapshot = OllamaLocalRuntimeObserver.Snapshot(
            observedAt: now,
            observeFailure: .version(.timeout)
        )
        let result = OllamaLocalModelDiscoveryProvider.result(from: snapshot, discoveredAt: now)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.diagnostics.map(\.code), ["OLLAMA_LOCAL_UNREACHABLE"])
        XCTAssertEqual(result.driverId, "ollama_local")
    }

    func testUnobservedYieldsNoCandidates() {
        let result = OllamaLocalModelDiscoveryProvider.result(from: nil, discoveredAt: now)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.diagnostics.map(\.code), ["OLLAMA_LOCAL_UNOBSERVED"])
    }

    func testReachableWithNoTagsIsEmptyNotAnOffer() {
        let snapshot = idleSnapshot(tags: [])
        let result = OllamaLocalModelDiscoveryProvider.result(from: snapshot, discoveredAt: now)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.diagnostics.map(\.code), ["OLLAMA_LOCAL_NO_TAGS"])
    }

    func testDiscoverUsesInjectedObserverTransportAndNotASecondClient() async {
        let transport = DiscoveryFixtureTransport(bodies: [
            #"{"version":"0.32.6"}"#,
            #"{"models":[{"name":"gpt-oss:20b"}]}"#,
            #"{"models":[]}"#,
        ])
        let provider = OllamaLocalModelDiscoveryProvider(
            transport: transport,
            isTestHost: true,
            now: now
        )
        let result = await provider.discover(invocation: nil)
        XCTAssertEqual(result.candidates.map(\.modelLabel), ["ollama/gpt-oss:20b"])
        XCTAssertEqual(transport.requestedPaths, ["/api/version", "/api/tags", "/api/ps"])
        XCTAssertTrue(result.candidates.allSatisfy { !$0.defaultEnabled })
        XCTAssertEqual(result.candidates.first?.origin, .discovered)
        XCTAssertEqual(result.candidates.first?.driverId, "ollama_local")
    }

    func testTestHostWithoutTransportDoesNotObserve() async {
        let provider = OllamaLocalModelDiscoveryProvider(
            transport: nil,
            isTestHost: true,
            now: now
        )
        let result = await provider.discover(invocation: nil)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.diagnostics.map(\.code), ["OLLAMA_LOCAL_UNOBSERVED"])
    }

    func testRegistryIsOllamaLocalNotABody() {
        XCTAssertNotNil(ModelDiscoveryRegistry.provider(for: "ollama_local"))
        XCTAssertNil(ModelDiscoveryRegistry.provider(for: "claude_code"))
        XCTAssertNil(ModelDiscoveryRegistry.provider(for: "opencode"))
        XCTAssertEqual(
            ModelDiscoveryRegistry.provider(for: "ollama_local")?.driverId,
            "ollama_local"
        )
    }

    func testExplicitEnableDisclosesMissingG1AndLowContextThenProceeds() {
        let candidate = OllamaLocalModelDiscoveryProvider.candidate(
            for: "qwen2.5:0.5b", discoveredAt: now)
        let assessment = OllamaLocalSeatEnablePolicy.assessExplicitEnable(
            candidate: candidate,
            bodyDriverId: "opencode",
            g1Passed: nil,
            servedContextWindow: 4096
        )
        XCTAssertTrue(assessment.permitsEnable)
        XCTAssertNil(assessment.refusal)
        XCTAssertFalse(assessment.automaticCodeOffer)
        XCTAssertEqual(assessment.boundSeat?.driverId, "opencode")
        XCTAssertEqual(assessment.boundSeat?.origin, .discovered)
        XCTAssertEqual(assessment.boundSeat?.defaultEnabled, false)
        XCTAssertEqual(assessment.boundSeat?.modelLabel, "ollama/qwen2.5:0.5b")
        XCTAssertEqual(assessment.boundSeat?.id, "discovered_opencode_qwen2_5_0_5b")
        XCTAssertTrue(assessment.disclosures.contains { $0.contains("runs on your Mac through Ollama") })
        XCTAssertTrue(assessment.disclosures.contains { $0.contains("adding it to OpenCode") })
        XCTAssertTrue(assessment.disclosures.contains { $0.contains("Allnighter has not tested this model") })
        XCTAssertTrue(assessment.disclosures.contains { $0.contains("4K") })
    }

    func testClaudeCodeBodyIsChosenAtEnableNotDiscovery() {
        let candidate = OllamaLocalModelDiscoveryProvider.candidate(
            for: "gpt-oss:20b", discoveredAt: now)
        XCTAssertEqual(candidate.driverId, "ollama_local")
        let claude = OllamaLocalSeatEnablePolicy.assessExplicitEnable(
            candidate: candidate,
            bodyDriverId: "claude_code",
            g1Passed: true,
            servedContextWindow: 131_072
        )
        XCTAssertTrue(claude.permitsEnable)
        XCTAssertEqual(claude.boundSeat?.driverId, "claude_code")
        XCTAssertEqual(claude.boundSeat?.id, "discovered_claude_code_gpt_oss_20b")
        XCTAssertTrue(claude.automaticCodeOffer)
        XCTAssertFalse(claude.disclosures.contains { $0.contains("Allnighter has not tested this model") })
        XCTAssertFalse(claude.disclosures.contains { $0.contains("below") })
    }

    func testAutomaticCodeOfferStaysGatedWithoutG1EvenWithLargeWindow() {
        XCTAssertFalse(
            OllamaLocalSeatEnablePolicy.allowsAutomaticCodeOffer(
                g1Passed: nil, servedContextWindow: 131_072)
        )
        XCTAssertFalse(
            OllamaLocalSeatEnablePolicy.allowsAutomaticCodeOffer(
                g1Passed: true, servedContextWindow: 4096)
        )
        XCTAssertTrue(
            OllamaLocalSeatEnablePolicy.allowsAutomaticCodeOffer(
                g1Passed: true, servedContextWindow: 65_536)
        )
    }

    func testUnknownBodyIsRefusedProvenanceIsNot() {
        let candidate = OllamaLocalModelDiscoveryProvider.candidate(
            for: "gpt-oss:20b", discoveredAt: now)
        let unknown = OllamaLocalSeatEnablePolicy.assessExplicitEnable(
            candidate: candidate,
            bodyDriverId: "codex",
            g1Passed: true,
            servedContextWindow: 131_072
        )
        XCTAssertFalse(unknown.permitsEnable)
        XCTAssertNil(unknown.boundSeat)
        XCTAssertTrue(unknown.refusal?.contains("unknown agent body") == true)

        let weak = OllamaLocalSeatEnablePolicy.assessExplicitEnable(
            candidate: candidate,
            bodyDriverId: "claude_code",
            g1Passed: false,
            servedContextWindow: 2048
        )
        XCTAssertTrue(weak.permitsEnable)
        XCTAssertNil(weak.refusal)
        XCTAssertEqual(weak.boundSeat?.driverId, "claude_code")
    }

    // MARK: - Helpers

    private func idleSnapshot(tags: [String]) -> OllamaLocalRuntimeObserver.Snapshot {
        OllamaLocalRuntimeObserver.snapshot(
            observedAt: now,
            ollamaVersion: "0.32.6",
            localTags: tags.map { .init(name: $0) },
            residentModels: []
        )
    }
}

private final class DiscoveryFixtureTransport: OllamaLocalRuntimeClient.Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [String]
    private(set) var requestedPaths: [String] = []

    init(bodies: [String]) {
        self.bodies = bodies
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        lock.lock()
        defer { lock.unlock() }
        let url = request.url!
        requestedPaths.append(url.path)
        let body = bodies.isEmpty ? "{}" : bodies.removeFirst()
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }
}
