import XCTest
@testable import AllnighterCore

/// OCL-S01b — doctor surfaces Ollama readiness only. Tests never open a socket.
final class OllamaLocalDoctorReportTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 0)
    private let observedAt = Date(timeIntervalSince1970: 1_754_000_000)
    private let models = [
        Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus", driverId: "claude_code", role: .both),
        Model(id: "model_codex", displayName: "GPT-5 Codex", modelLabel: "gpt", driverId: "codex", role: .answerer),
    ]
    private let manifests = [
        DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
        DriverManifest(id: "codex", displayName: "Codex", kind: .headlessCLI),
    ]

    private var readyRecords: [ToolProbeRecord] {
        [
            ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1.2"), version: "1.2", lastProbeAt: t),
            ToolProbeRecord(driverId: "codex", status: .ready(version: "0.9"), version: "0.9", lastProbeAt: t),
        ]
    }

    func testCheckNamesAreContractListed() {
        let names = ContractRegistry.milestone1.doctorChecks.map(\.name)
        for name in OllamaLocalDoctorReport.checkNames {
            XCTAssertTrue(names.contains(name), "missing doctor check \(name)")
        }
    }

    func testTestHostWithoutTransportDoesNotObserve() {
        let recording = RecordingTransport()
        let skipped = OllamaLocalDoctorReport.snapshotIfAllowed(
            transport: nil,
            observedAt: observedAt,
            isTestHost: true
        )
        XCTAssertNil(skipped)
        XCTAssertEqual(recording.requestCount, 0)
    }

    func testInjectedTransportIsUsedEvenOnTestHost() {
        let transport = RecordingTransport(error: URLError(.cannotConnectToHost))
        let snap = OllamaLocalDoctorReport.snapshotIfAllowed(
            transport: transport,
            observedAt: observedAt,
            isTestHost: true
        )
        XCTAssertEqual(snap?.readiness, .unavailable)
        XCTAssertGreaterThan(transport.requestCount, 0)
        XCTAssertEqual(transport.requestedPaths.first, "/api/version")
    }

    func testOllamaAbsentLeavesPaidDoctorUntouched() {
        let baseline = build(snapshot: nil)
        let absent = build(snapshot: unavailableSnapshot())

        XCTAssertEqual(paidFingerprint(baseline), paidFingerprint(absent))
        XCTAssertEqual(absent.status, baseline.status)
        XCTAssertEqual(absent.nextActions, baseline.nextActions)
        XCTAssertEqual(absent.models, baseline.models)

        XCTAssertNil(check(baseline, OllamaLocalDoctorReport.readinessCheckName))
        XCTAssertEqual(check(absent, OllamaLocalDoctorReport.readinessCheckName)?.detail, "Unavailable")
        XCTAssertEqual(check(absent, OllamaLocalDoctorReport.reachableCheckName)?.detail, "not reachable")
        XCTAssertEqual(check(absent, OllamaLocalDoctorReport.modelsCheckName)?.detail, "none")
        XCTAssertEqual(check(absent, OllamaLocalDoctorReport.readinessCheckName)?.status, .ok)
        XCTAssertEqual(check(absent, "source.claude_code.installed")?.status, .ok)
        XCTAssertEqual(check(absent, "source.codex.installed")?.status, .ok)
        XCTAssertEqual(check(absent, "benchReadyCount")?.detail, check(baseline, "benchReadyCount")?.detail)
    }

    func testIdleListsPulledModelsAndExactReadinessWord() {
        let snap = OllamaLocalRuntimeObserver.snapshot(
            observedAt: observedAt,
            ollamaVersion: "0.32.6",
            localTags: [
                .init(name: "qwen2.5:0.5b"),
                .init(name: "qwen2.5-coder:7b"),
            ],
            residentModels: []
        )
        let r = build(snapshot: snap)
        XCTAssertEqual(check(r, OllamaLocalDoctorReport.readinessCheckName)?.detail, "Idle")
        XCTAssertEqual(check(r, OllamaLocalDoctorReport.reachableCheckName)?.detail, "reachable (0.32.6)")
        XCTAssertEqual(
            check(r, OllamaLocalDoctorReport.modelsCheckName)?.detail,
            "qwen2.5:0.5b, qwen2.5-coder:7b"
        )
        XCTAssertEqual(r.status, .ok)
        assertNoCapacityLanguage(r)
    }

    func testBusyDoesNotLeakServedContextOrCapacityMeters() {
        let snap = OllamaLocalRuntimeObserver.Snapshot(
            readiness: .busy,
            observedAt: observedAt,
            ollamaVersion: "0.32.6",
            localTags: [.init(name: "qwen2.5:0.5b")],
            residentModels: [.init(name: "qwen2.5:0.5b", servedContextWindow: 4096)]
        )
        let r = build(snapshot: snap)
        XCTAssertEqual(check(r, OllamaLocalDoctorReport.readinessCheckName)?.detail, "Busy")
        let ollamaDetails = r.checks
            .filter { $0.name.hasPrefix("source.ollama_local.") }
            .map(\.detail)
            .joined(separator: " ")
        XCTAssertFalse(ollamaDetails.contains("4096"), ollamaDetails)
        assertNoCapacityLanguage(r)
        XCTAssertEqual(paidFingerprint(r), paidFingerprint(build(snapshot: nil)))
    }

    func testReadinessDetailIsExactlyOneOfThreeWords() {
        for word in ["Unavailable", "Idle", "Busy"] {
            let readiness = OllamaLocalRuntimeObserver.Readiness(rawValue: word)!
            let snap = OllamaLocalRuntimeObserver.Snapshot(
                readiness: readiness,
                observedAt: observedAt,
                ollamaVersion: word == "Unavailable" ? nil : "0.32.6",
                localTags: word == "Unavailable" ? [] : [.init(name: "qwen2.5:0.5b")],
                residentModels: word == "Busy" ? [.init(name: "qwen2.5:0.5b", servedContextWindow: 8192)] : []
            )
            let detail = OllamaLocalDoctorReport.checks(from: snap)
                .first { $0.name == OllamaLocalDoctorReport.readinessCheckName }?
                .detail
            XCTAssertEqual(detail, word)
        }
    }

    func testOllamaLocalIsNotACapacityBenchSource() {
        XCTAssertFalse(CapacityAcquisition.benchSourceOrder.contains(OllamaLocalRuntimeClient.sourceId))
        XCTAssertFalse(CapacityStripRenderer.displayOrder.contains(OllamaLocalRuntimeClient.sourceId))
        XCTAssertEqual(OllamaLocalRuntimeClient.sourceId, "ollama_local")
    }

    // MARK: - Helpers

    private func inputs(snapshot: OllamaLocalRuntimeObserver.Snapshot?) -> DoctorReport.Inputs {
        .init(
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0",
            configDirWritable: true,
            runsDirWritable: true,
            full: true,
            openCodeGoCapacity: .failure(.notConfigured),
            ollamaLocal: snapshot
        )
    }

    private func build(snapshot: OllamaLocalRuntimeObserver.Snapshot?) -> DoctorResult {
        DoctorReport.build(
            models: models,
            manifests: manifests,
            records: readyRecords,
            inputs: inputs(snapshot: snapshot)
        )
    }

    private func unavailableSnapshot() -> OllamaLocalRuntimeObserver.Snapshot {
        OllamaLocalRuntimeObserver.Snapshot(
            readiness: .unavailable,
            observedAt: observedAt,
            observeFailure: .version(.network("connection refused"))
        )
    }

    private func check(_ r: DoctorResult, _ name: String) -> DoctorResult.Check? {
        r.checks.first { $0.name == name }
    }

    private func paidFingerprint(_ r: DoctorResult) -> PaidDoctorFingerprint {
        PaidDoctorFingerprint(
            status: r.status,
            checks: r.checks
                .filter { !$0.name.hasPrefix("source.ollama_local.") }
                .map { PaidCheck(name: $0.name, status: $0.status, detail: $0.detail, fixCommand: $0.fixCommand) },
            models: r.models,
            nextActions: r.nextActions
        )
    }

    private func assertNoCapacityLanguage(_ r: DoctorResult) {
        let blob = r.checks
            .filter { $0.name.hasPrefix("source.ollama_local.") }
            .map { "\($0.name) \($0.detail) \($0.fixCommand ?? "")" }
            .joined(separator: "\n")
            .lowercased()
        for token in ["%", "vram", "5h", "weekly", "context"] {
            XCTAssertFalse(blob.contains(token), "capacity language leaked: \(token)\n\(blob)")
        }
    }
}

private struct PaidCheck: Equatable {
    var name: String
    var status: DoctorResult.CheckStatus
    var detail: String
    var fixCommand: String?
}

private struct PaidDoctorFingerprint: Equatable {
    var status: DoctorResult.Status
    var checks: [PaidCheck]
    var models: [TeamRunJSON.ModelInfo]
    var nextActions: [AgentSurfaceNextAction]
}

private final class RecordingTransport: OllamaLocalRuntimeClient.Transport, @unchecked Sendable {
    private let lock = NSLock()
    private let error: Error?
    private(set) var requestedURLs: [URL] = []

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestedURLs.count
    }

    var requestedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestedURLs.map(\.path)
    }

    init(error: Error? = nil) {
        self.error = error
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        lock.lock()
        requestedURLs.append(request.url!)
        lock.unlock()
        if let error { throw error }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(#"{"version":"0.32.6"}"#.utf8), response)
    }
}
