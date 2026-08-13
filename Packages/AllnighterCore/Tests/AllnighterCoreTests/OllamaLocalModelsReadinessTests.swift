import XCTest
@testable import AllnighterCore

/// OCL-S04 — `alln models` surfaces Ollama readiness from the S01b projection.
/// Tests never open a socket.
final class OllamaLocalModelsReadinessTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_754_000_000)
    private let registry = DriverRegistry([
        DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
        DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
        DriverManifest(id: "codex", displayName: "Codex", kind: .headlessCLI),
    ])
    private let paid = ModelDefinition(
        id: "model_opus", displayName: "Opus 5", modelLabel: "opus",
        driverId: "claude_code", role: .both, origin: .builtIn, defaultEnabled: true,
        capabilities: ModelCapabilities())
    private let localClaude = ModelDefinition(
        id: "custom_claude_ollama_qwen", displayName: "Qwen local",
        modelLabel: "ollama/qwen2.5:0.5b",
        driverId: "claude_code", role: .answerer, origin: .custom, defaultEnabled: true,
        capabilities: ModelCapabilities())
    private let localOpenCode = ModelDefinition(
        id: "custom_opencode_ollama_qwen", displayName: "Qwen OpenCode",
        modelLabel: "ollama/qwen2.5:0.5b",
        driverId: "opencode", role: .answerer, origin: .custom, defaultEnabled: true,
        capabilities: ModelCapabilities())
    private let paidOpenCode = ModelDefinition(
        id: "model_opencode_go", displayName: "Go seat", modelLabel: "opencode-go/kimi",
        driverId: "opencode", role: .answerer, origin: .builtIn, defaultEnabled: true,
        capabilities: ModelCapabilities())

    func testReadinessWordMatchesDoctorCheck() {
        for word in ["Unavailable", "Idle", "Busy"] {
            let snap = snapshot(word)
            let doctor = OllamaLocalDoctorReport.checks(from: snap)
                .first { $0.name == OllamaLocalDoctorReport.readinessCheckName }?
                .detail
            XCTAssertEqual(OllamaLocalDoctorReport.readinessWord(from: snap), doctor)
            XCTAssertEqual(OllamaLocalDoctorReport.readinessWord(from: snap), word)
        }
    }

    func testLocalSeatShowsExactThreeWords() throws {
        for word in ["Unavailable", "Idle", "Busy"] {
            let list = build(snapshot: snapshot(word))
            let row = try XCTUnwrap(list.models.first { $0.id == localClaude.id })
            XCTAssertEqual(row.readiness, word)
            XCTAssertEqual(try encoded(row)["readiness"] as? String, word)
        }
    }

    func testOpenCodeLocalSeatUsesSameProjection() throws {
        let list = build(snapshot: snapshot("Busy"))
        let row = try XCTUnwrap(list.models.first { $0.id == localOpenCode.id })
        XCTAssertEqual(row.readiness, "Busy")
        XCTAssertEqual(
            row.readiness,
            OllamaLocalDoctorReport.readinessWord(from: snapshot("Busy"))
        )
    }

    func testPaidRowsDoNotChangeShapeWhenOllamaIsDown() throws {
        let baseline = build(snapshot: nil)
        let absent = build(snapshot: snapshot("Unavailable"))

        let paidIds = [paid.id, paidOpenCode.id]
        for id in paidIds {
            let before = try XCTUnwrap(baseline.models.first { $0.id == id })
            let after = try XCTUnwrap(absent.models.first { $0.id == id })
            XCTAssertNil(before.readiness)
            XCTAssertNil(after.readiness)
            XCTAssertEqual(try encodedKeys(before), try encodedKeys(after))
            XCTAssertEqual(try CoreJSON.encode(before), try CoreJSON.encode(after))
        }

        let local = try XCTUnwrap(absent.models.first { $0.id == localClaude.id })
        XCTAssertEqual(local.readiness, "Unavailable")
        XCTAssertTrue(try encodedKeys(local).contains("readiness"))
        XCTAssertFalse(
            try encodedKeys(try XCTUnwrap(absent.models.first { $0.id == paid.id })).contains("readiness")
        )
    }

    func testNilSnapshotOmitsReadinessEvenOnLocalSeats() throws {
        let list = build(snapshot: nil)
        XCTAssertTrue(list.models.allSatisfy { $0.readiness == nil })
        for row in list.models {
            XCTAssertFalse(try encodedKeys(row).contains("readiness"))
        }
    }

    func testBusyDoesNotLeakServedContextOrCapacityLanguage() throws {
        let snap = OllamaLocalRuntimeObserver.Snapshot(
            readiness: .busy,
            observedAt: observedAt,
            ollamaVersion: "0.32.6",
            localTags: [.init(name: "qwen2.5:0.5b")],
            residentModels: [.init(name: "qwen2.5:0.5b", servedContextWindow: 4096)]
        )
        let list = build(snapshot: snap)
        let row = try XCTUnwrap(list.models.first { $0.id == localClaude.id })
        XCTAssertEqual(row.readiness, "Busy")
        let blob = try String(data: CoreJSON.encode(row), encoding: .utf8)!
        XCTAssertFalse(blob.contains("4096"), blob)
        let lower = blob.lowercased()
        for token in ["%", "vram", "5h", "weekly", "context", "quota", "reset"] {
            XCTAssertFalse(lower.contains(token), "capacity language leaked: \(token)\n\(blob)")
        }
    }

    func testOllamaLocalIsNotACapacityBenchSource() {
        XCTAssertFalse(CapacityAcquisition.benchSourceOrder.contains(OllamaLocalRuntimeClient.sourceId))
        XCTAssertFalse(CapacityStripRenderer.displayOrder.contains(OllamaLocalRuntimeClient.sourceId))
        XCTAssertEqual(OllamaLocalRuntimeClient.sourceId, "ollama_local")
        XCTAssertTrue(OllamaLocalDoctorReport.isOllamaBackedSeat(modelLabel: "ollama/qwen2.5:0.5b"))
        XCTAssertFalse(OllamaLocalDoctorReport.isOllamaBackedSeat(modelLabel: "opus"))
        XCTAssertFalse(OllamaLocalDoctorReport.isOllamaBackedSeat(modelLabel: "opencode-go/kimi"))
    }

    func testTestHostWithoutTransportDoesNotObserve() {
        let skipped = OllamaLocalDoctorReport.snapshotIfAllowed(
            transport: nil,
            observedAt: observedAt,
            isTestHost: true
        )
        XCTAssertNil(skipped)
    }

    // MARK: - Helpers

    private func build(snapshot: OllamaLocalRuntimeObserver.Snapshot?) -> ModelListJSON {
        ModelListProjector.build(
            registry: registry,
            definitions: [paid, localClaude, localOpenCode, paidOpenCode],
            probeRecords: [],
            diagnostics: [],
            ollamaLocal: snapshot
        )
    }

    private func snapshot(_ word: String) -> OllamaLocalRuntimeObserver.Snapshot {
        let readiness = OllamaLocalRuntimeObserver.Readiness(rawValue: word)!
        return OllamaLocalRuntimeObserver.Snapshot(
            readiness: readiness,
            observedAt: observedAt,
            ollamaVersion: word == "Unavailable" ? nil : "0.32.6",
            localTags: word == "Unavailable" ? [] : [.init(name: "qwen2.5:0.5b")],
            residentModels: word == "Busy" ? [.init(name: "qwen2.5:0.5b", servedContextWindow: 8192)] : []
        )
    }

    private func encoded(_ entry: ModelListJSON.Entry) throws -> [String: Any] {
        let data = try CoreJSON.encode(entry)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encodedKeys(_ entry: ModelListJSON.Entry) throws -> Set<String> {
        Set(try encoded(entry).keys)
    }
}
