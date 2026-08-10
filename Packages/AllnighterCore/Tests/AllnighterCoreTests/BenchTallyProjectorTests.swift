import XCTest
import AgentOSCLI
@testable import AllnighterCore

final class BenchTallyProjectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func manifest(_ id: String, kind: DriverKind = .headlessCLI) -> DriverManifest {
        DriverManifest(id: id, displayName: id, kind: kind)
    }

    private func registry(_ ids: [String], extra: [DriverManifest] = []) -> DriverRegistry {
        DriverRegistry(ids.map { manifest($0) } + extra)
    }

    private func record(
        _ id: String,
        _ status: ModelSetupStatus,
        at ageSeconds: TimeInterval = 0
    ) -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: id,
            status: status,
            lastProbeAt: now.addingTimeInterval(-ageSeconds)
        )
    }

    private func rateLimited(
        confidence: CapacitySourceConfidence = .structured,
        retryAfterSeconds: Int? = 3600
    ) -> ModelSetupStatus {
        .rateLimited(observation: CapacityObservation(
            kind: .accountRateLimit, source: "kimi", sourceConfidence: confidence,
            rawSnippet: "kimi", observedAt: now, retryAfterSeconds: retryAfterSeconds
        ))
    }

    // MARK: - Headlines

    func testEmptyRegistryIsConfigurationMissing() {
        let tally = BenchTallyProjector.tally(
            registry: DriverRegistry([]), records: [], now: now
        )
        XCTAssertEqual(tally.headline, .configurationMissing)
        XCTAssertEqual(tally.supported, 0)
        XCTAssertEqual(tally.measured, 0)
    }

    func testEmptyRecordsIsNeverScannedWithNoRatioShape() {
        let tally = BenchTallyProjector.tally(
            registry: registry(["claude_code", "codex", "cursor_agent"]),
            records: [],
            now: now
        )
        XCTAssertEqual(tally.headline, .neverScanned)
        XCTAssertEqual(tally.supported, 3)
        XCTAssertEqual(tally.measured, 0)
        XCTAssertEqual(tally.ready, 0)
        XCTAssertEqual(tally.needsCheck, 3)
        // Callers must not invent ready/supported as a grade — headline owns it.
        XCTAssertNotEqual(tally.headline, .noneReady)
    }

    func testManualPasteDoesNotCountAsSupported() {
        let tally = BenchTallyProjector.tally(
            registry: DriverRegistry([
                manifest("claude_code"),
                manifest("manual_paste", kind: .manualPaste),
            ]),
            records: [],
            now: now
        )
        XCTAssertEqual(tally.supported, 1)
        XCTAssertEqual(tally.headline, .neverScanned)
    }

    func testParkedExcludedFromEveryBucket() {
        let tally = BenchTallyProjector.tally(
            registry: registry(["claude_code", "codex"]),
            records: [
                record("claude_code", .ready(version: "1")),
                record("codex", .ready(version: "1")),
            ],
            parked: ["codex"],
            now: now
        )
        XCTAssertEqual(tally.supported, 1)
        XCTAssertEqual(tally.ready, 1)
        XCTAssertEqual(tally.headline, .allReady)
    }

    func testUnknownManifestRecordsIgnored() {
        let tally = BenchTallyProjector.tally(
            registry: registry(["claude_code"]),
            records: [
                record("claude_code", .ready(version: "1")),
                record("ghost_cli", .ready(version: "9")),
            ],
            now: now
        )
        XCTAssertEqual(tally.supported, 1)
        XCTAssertEqual(tally.ready, 1)
        XCTAssertEqual(tally.measured, 1)
        XCTAssertEqual(tally.headline, .allReady)
    }

    func testDuplicateRecordsDedupeByLatestProbe() {
        let older = record("claude_code", .probeFailed(reason: "old"), at: 120)
        let newer = record("claude_code", .ready(version: "2"), at: 5)
        let tally = BenchTallyProjector.tally(
            registry: registry(["claude_code"]),
            records: [older, newer],
            now: now
        )
        XCTAssertEqual(tally.ready, 1)
        XCTAssertEqual(tally.needsStep, 0)
        XCTAssertEqual(tally.headline, .allReady)
    }

    func testPartialAndAllReadyAndNoneReady() {
        let partial = BenchTallyProjector.tally(
            registry: registry(["a", "b", "c"]),
            records: [
                record("a", .ready(version: "1")),
                record("b", .notInstalled),
                record("c", .installedNotSignedIn(
                    LoginFlow(interactiveCommand: "x", instructions: "login"))),
            ],
            now: now
        )
        XCTAssertEqual(partial.headline, .partial)
        XCTAssertEqual(partial.ready, 1)
        XCTAssertEqual(partial.notInstalled, 1)
        XCTAssertEqual(partial.needsStep, 1)

        let allReady = BenchTallyProjector.tally(
            registry: registry(["a", "b"]),
            records: [
                record("a", .ready(version: "1")),
                record("b", .ready(version: "1")),
            ],
            now: now
        )
        XCTAssertEqual(allReady.headline, .allReady)
        XCTAssertEqual(allReady.ready, 2)

        let none = BenchTallyProjector.tally(
            registry: registry(["a", "b"]),
            records: [
                record("a", .notInstalled),
                record("b", .probeFailed(reason: "nope")),
            ],
            now: now
        )
        XCTAssertEqual(none.headline, .noneReady)
        XCTAssertEqual(none.ready, 0)
        XCTAssertEqual(none.notInstalled, 1)
        XCTAssertEqual(none.needsStep, 1)
    }

    func testInstalledNotProbedGoesToNeedsCheck() {
        let tally = BenchTallyProjector.tally(
            registry: registry(["claude_code"]),
            records: [record("claude_code", .installedNotProbed(version: "1"))],
            now: now
        )
        XCTAssertEqual(tally.headline, .noneReady)
        XCTAssertEqual(tally.needsCheck, 1)
        XCTAssertEqual(tally.needsStep, 0)
        XCTAssertEqual(tally.measured, 1)
    }

    func testStaleAndInferredNegativesAreNeedsCheckNotNeedsStep() {
        let stale = record(
            "kimi",
            rateLimited(confidence: .structured, retryAfterSeconds: 3600),
            at: 38 * 3600
        )
        let inferred = record(
            "grok",
            rateLimited(confidence: .localPolicy, retryAfterSeconds: 3600),
            at: 60
        )
        let freshFail = record("codex", .probeFailed(reason: "timeout"), at: 30)

        let tally = BenchTallyProjector.tally(
            registry: registry(["kimi", "grok", "codex"]),
            records: [stale, inferred, freshFail],
            now: now
        )
        XCTAssertEqual(tally.needsCheck, 2, "stale + inferred must not stay needsStep")
        XCTAssertEqual(tally.needsStep, 1, "fresh probeFailed stays needsStep")
        XCTAssertEqual(tally.headline, .noneReady)
    }

    func testDetectCommandIsRegistryResolvableName() {
        XCTAssertEqual(BenchTallyProjector.detectCommand, "alln detect")
    }
}
