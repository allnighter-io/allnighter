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
    private let missingTag = ModelDefinition(
        id: "custom_claude_ollama_gptoss", displayName: "gpt-oss local",
        modelLabel: "ollama/gpt-oss:20b",
        driverId: "claude_code", role: .answerer, origin: .custom, defaultEnabled: true,
        capabilities: ModelCapabilities())
    private let paidOpenCode = ModelDefinition(
        id: "model_opencode_go", displayName: "Go seat", modelLabel: "opencode-go/kimi",
        driverId: "opencode", role: .answerer, origin: .builtIn, defaultEnabled: true,
        capabilities: ModelCapabilities())

    func testReadinessWordMatchesDoctorCheck() {
        let snap = pulledSnapshot(resident: false)
        let doctor = OllamaLocalDoctorReport.checks(
            from: snap,
            localSeatLabels: [localClaude.modelLabel]
        )
            .first { $0.name == OllamaLocalDoctorReport.readinessCheckName }?
            .detail
        let word = OllamaLocalDoctorReport.readinessWord(
            from: snap, modelLabel: localClaude.modelLabel)
        XCTAssertEqual(word, "Available")
        XCTAssertEqual(doctor, "qwen2.5:0.5b: Available")
        XCTAssertTrue(doctor?.contains(word) == true)
    }

    func testLocalSeatShowsExactTwoWords() throws {
        let available = build(snapshot: pulledSnapshot(resident: false))
        let availableRow = try XCTUnwrap(available.models.first { $0.id == localClaude.id })
        XCTAssertEqual(availableRow.readiness, "Available")
        XCTAssertEqual(try encoded(availableRow)["readiness"] as? String, "Available")

        let down = build(snapshot: downSnapshot())
        let downRow = try XCTUnwrap(down.models.first { $0.id == localClaude.id })
        XCTAssertEqual(downRow.readiness, "Unavailable")
        XCTAssertEqual(try encoded(downRow)["readiness"] as? String, "Unavailable")
    }

    func testPerSeatNotPerRuntime() throws {
        let list = build(snapshot: pulledSnapshot(resident: true), extra: [missingTag])
        let pulled = try XCTUnwrap(list.models.first { $0.id == localClaude.id })
        let missing = try XCTUnwrap(list.models.first { $0.id == missingTag.id })
        XCTAssertEqual(pulled.readiness, "Available")
        XCTAssertEqual(missing.readiness, "Unavailable")
        XCTAssertEqual(
            pulled.readiness,
            OllamaLocalDoctorReport.readinessWord(from: pulledSnapshot(resident: true), modelLabel: localClaude.modelLabel)
        )
        XCTAssertEqual(
            missing.readiness,
            OllamaLocalDoctorReport.readinessWord(from: pulledSnapshot(resident: true), modelLabel: missingTag.modelLabel)
        )
    }

    func testOpenCodeLocalSeatUsesSameProjection() throws {
        let snap = pulledSnapshot(resident: true)
        let list = build(snapshot: snap)
        let row = try XCTUnwrap(list.models.first { $0.id == localOpenCode.id })
        XCTAssertEqual(row.readiness, "Available")
        XCTAssertEqual(
            row.readiness,
            OllamaLocalDoctorReport.readinessWord(from: snap, modelLabel: localOpenCode.modelLabel)
        )
    }

    func testPaidRowsDoNotChangeShapeWhenOllamaIsDown() throws {
        let baseline = build(snapshot: nil)
        let absent = build(snapshot: downSnapshot())

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

    func testResidentDoesNotLeakServedContextOrCapacityLanguage() throws {
        let snap = pulledSnapshot(resident: true)
        let list = build(snapshot: snap)
        let row = try XCTUnwrap(list.models.first { $0.id == localClaude.id })
        XCTAssertEqual(row.readiness, "Available")
        let blob = try String(data: CoreJSON.encode(row), encoding: .utf8)!
        XCTAssertFalse(blob.contains("4096"), blob)
        XCTAssertFalse(blob.contains("Idle"), blob)
        XCTAssertFalse(blob.contains("Busy"), blob)
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

    private func build(
        snapshot: OllamaLocalRuntimeObserver.Snapshot?,
        extra: [ModelDefinition] = []
    ) -> ModelListJSON {
        ModelListProjector.build(
            registry: registry,
            definitions: [paid, localClaude, localOpenCode, paidOpenCode] + extra,
            probeRecords: [],
            diagnostics: [],
            ollamaLocal: snapshot
        )
    }

    private func pulledSnapshot(resident: Bool) -> OllamaLocalRuntimeObserver.Snapshot {
        OllamaLocalRuntimeObserver.Snapshot(
            observedAt: observedAt,
            ollamaVersion: "0.32.6",
            localTags: [.init(name: "qwen2.5:0.5b")],
            residentModels: resident
                ? [.init(name: "qwen2.5:0.5b", servedContextWindow: 4096)]
                : []
        )
    }

    private func downSnapshot() -> OllamaLocalRuntimeObserver.Snapshot {
        OllamaLocalRuntimeObserver.Snapshot(
            observedAt: observedAt,
            observeFailure: .version(.network("connection refused"))
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
