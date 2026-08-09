import XCTest
import AgentOSCLI
@testable import AllnighterCore

/// PF-S01 — every driver/model row must disclose how old its evidence is:
/// `checkedAt` + `ageMinutes` + `stale`, plus a `nextAction` that actually
/// refreshes it. Disclosure only — PF-S00 (already shipped) owns whether a
/// stale NEGATIVE may still be asserted; this file is strictly about the age
/// fields, not about status/ready/blockedReason.
///
/// Works Test (`docs/phases/Probe_Freshness.md` §PF-S01):
///   Given: cli_setup.json last written 38h ago
///   When:  alln menu --json
///   Then:  every driver/model row carries checkedAt + ageMinutes
///   And:   stale == true, with a nextAction whose command actually refreshes
///   And:   a never-probed row reports checkedAt: null, not a fabricated time
final class ProbeFreshnessDisclosureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func freshRecord(driverId: String, ageSeconds: TimeInterval) -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: driverId, status: .ready(version: "1.0"),
            lastProbeAt: now.addingTimeInterval(-ageSeconds))
    }

    // MARK: - alln drivers --json

    /// The dogfood shape: a record 38 hours old must disclose real age and
    /// `stale: true` — never a fabricated "just checked" timestamp.
    func testDriverRowDisclosesAgeOnA38HourStaleRecord() {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let record = freshRecord(driverId: "kimi", ageSeconds: 38 * 3600)
        let list = DriverListProjector.build(
            registry: registry, probeRecords: [record], now: now, models: [], parkedDriverIds: [])
        let row = try! XCTUnwrap(list.drivers.first)
        XCTAssertEqual(row.freshness.checkedAt, record.lastProbeAt)
        XCTAssertEqual(row.freshness.ageMinutes, 38 * 60)
        XCTAssertTrue(row.freshness.stale)
        XCTAssertEqual(row.freshness.evidenceSource, "probe")
        // Must actually refresh THIS driver's record — verified live in the
        // closeout report by running it, not merely asserting the string.
        XCTAssertEqual(row.freshness.nextAction.command, "alln doctor --full --agent kimi")
    }

    /// Control: a fresh record (5 minutes old) is disclosed with an accurate
    /// small age and `stale: false` — proves the field distinguishes fresh
    /// from stale rather than always asserting one value.
    func testDriverRowDisclosesFreshRecordAsNotStale() {
        let registry = DriverRegistry([
            DriverManifest(id: "grok", displayName: "Grok", kind: .headlessCLI),
        ])
        let record = freshRecord(driverId: "grok", ageSeconds: 300)
        let list = DriverListProjector.build(
            registry: registry, probeRecords: [record], now: now, models: [], parkedDriverIds: [])
        let row = try! XCTUnwrap(list.drivers.first)
        XCTAssertEqual(row.freshness.checkedAt, record.lastProbeAt)
        XCTAssertEqual(row.freshness.ageMinutes, 5)
        XCTAssertFalse(row.freshness.stale)
        XCTAssertEqual(row.freshness.nextAction.command, "alln doctor --full --agent grok")
    }

    /// Control: a driver with NO probe record at all reports `checkedAt: nil`
    /// — never epoch zero, never `now`, never a fabricated positive.
    func testNeverProbedDriverRowReportsNullCheckedAt() {
        let registry = DriverRegistry([
            DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
        ])
        let list = DriverListProjector.build(
            registry: registry, probeRecords: [], now: now, models: [], parkedDriverIds: [])
        let row = try! XCTUnwrap(list.drivers.first)
        XCTAssertNil(row.freshness.checkedAt)
        XCTAssertNil(row.freshness.ageMinutes)
        XCTAssertTrue(row.freshness.stale)
        XCTAssertEqual(row.freshness.nextAction.command, "alln doctor --full --agent opencode")
    }

    /// The literal wire proof: an omitted key and an explicit `null` decode
    /// identically in Swift, so `XCTAssertNil` alone cannot catch a wrong
    /// choice between them — this asserts the actual JSON bytes. Swift's
    /// synthesized `Encodable` calls `encodeIfPresent` for `Optional`
    /// properties, which OMITS the key on nil; the packet requires an
    /// explicit `null`, so `ProbeFreshnessJSON` hand-writes `encode(to:)`.
    func testNeverProbedRowEmitsLiteralNullNotAnOmittedKey() throws {
        let registry = DriverRegistry([
            DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
        ])
        let list = DriverListProjector.build(
            registry: registry, probeRecords: [], now: now, models: [], parkedDriverIds: [])
        let data = try CoreJSON.encode(list)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"checkedAt\""), "checkedAt key must be present on the wire")
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let drivers = try XCTUnwrap(obj["drivers"] as? [[String: Any]])
        let row = try XCTUnwrap(drivers.first)
        let freshness = try XCTUnwrap(row["freshness"] as? [String: Any])
        XCTAssertTrue(
            freshness.keys.contains("checkedAt"),
            "checkedAt must be a present key (explicit null), never an omitted one")
        XCTAssertTrue(freshness["checkedAt"] is NSNull, "a never-probed row's checkedAt must decode as null")
        XCTAssertTrue(
            freshness.keys.contains("ageMinutes"),
            "ageMinutes must be a present key (explicit null), never an omitted one")
        XCTAssertTrue(freshness["ageMinutes"] is NSNull)
    }

    /// Read-time only, same law as `ProbeFreshnessGate`: disclosure must never
    /// rewrite the stored record. PF-S01 needs the ORIGINAL `lastProbeAt` to
    /// report age honestly — a projection that normalizes it destroys the
    /// very thing being disclosed.
    func testDisclosureNeverMutatesTheStoredRecord() {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let record = freshRecord(driverId: "kimi", ageSeconds: 38 * 3600)
        let before = record
        _ = DriverListProjector.build(
            registry: registry, probeRecords: [record], now: now, models: [], parkedDriverIds: [])
        XCTAssertEqual(record, before)
        XCTAssertEqual(record.lastProbeAt, before.lastProbeAt)
    }

    // MARK: - alln models --json

    /// A model row must never present the driver's checkedAt as if the MODEL
    /// itself were probed — `evidenceSource: "driver"` makes the inheritance
    /// explicit rather than implied.
    func testModelRowInheritsDriverEvidenceAndDisclosesIt() {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let record = freshRecord(driverId: "kimi", ageSeconds: 38 * 3600)
        let definitions = [
            ModelDefinition(
                id: "model_kimi_k3", displayName: "Kimi K3", modelLabel: "kimi-k3",
                driverId: "kimi", role: .both, origin: .builtIn, defaultEnabled: true,
                capabilities: ModelCapabilities()),
        ]
        let list = ModelListProjector.build(
            registry: registry, definitions: definitions, probeRecords: [record], now: now,
            diagnostics: [])
        let row = try! XCTUnwrap(list.models.first { $0.id == "model_kimi_k3" })
        XCTAssertEqual(row.freshness.checkedAt, record.lastProbeAt)
        XCTAssertEqual(row.freshness.ageMinutes, 38 * 60)
        XCTAssertTrue(row.freshness.stale)
        XCTAssertEqual(row.freshness.evidenceSource, "driver", "a model is never independently probed")
        XCTAssertEqual(row.freshness.nextAction.command, "alln doctor --full --agent kimi")
    }

    /// Control: a never-probed driver's model reports `checkedAt: nil` too —
    /// the model has no evidence of its own to fabricate one from either.
    func testModelRowForNeverProbedDriverReportsNullCheckedAt() {
        let registry = DriverRegistry([
            DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
        ])
        let definitions = [
            ModelDefinition(
                id: "model_oc", displayName: "OC", modelLabel: "oc",
                driverId: "opencode", role: .both, origin: .builtIn, defaultEnabled: true,
                capabilities: ModelCapabilities()),
        ]
        let list = ModelListProjector.build(
            registry: registry, definitions: definitions, probeRecords: [], now: now,
            diagnostics: [])
        let row = try! XCTUnwrap(list.models.first { $0.id == "model_oc" })
        XCTAssertNil(row.freshness.checkedAt)
        XCTAssertNil(row.freshness.ageMinutes)
        XCTAssertTrue(row.freshness.stale)
        XCTAssertEqual(row.freshness.evidenceSource, "driver")
    }

    /// Control: a fresh driver's model is disclosed as not stale.
    func testModelRowForFreshDriverIsNotStale() {
        let registry = DriverRegistry([
            DriverManifest(id: "grok", displayName: "Grok", kind: .headlessCLI),
        ])
        let record = freshRecord(driverId: "grok", ageSeconds: 300)
        let definitions = [
            ModelDefinition(
                id: "model_grok", displayName: "Grok", modelLabel: "grok",
                driverId: "grok", role: .both, origin: .builtIn, defaultEnabled: true,
                capabilities: ModelCapabilities()),
        ]
        let list = ModelListProjector.build(
            registry: registry, definitions: definitions, probeRecords: [record], now: now,
            diagnostics: [])
        let row = try! XCTUnwrap(list.models.first { $0.id == "model_grok" })
        XCTAssertEqual(row.freshness.ageMinutes, 5)
        XCTAssertFalse(row.freshness.stale)
    }

    // MARK: - alln menu --json (Tier-1 front door)

    /// The menu is the primary agent front door named by the Works Test.
    /// `MenuCatalog.project` is fed `ModelListJSON.Entry` rows built by
    /// `ModelListProjector`, so freshness must survive that hand-off into
    /// `MenuJSON.Model.freshness` unchanged — never re-derived, never dropped.
    func testMenuModelRowCarriesTheSameFreshnessAsTheModelListEntry() {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let record = freshRecord(driverId: "kimi", ageSeconds: 38 * 3600)
        let definitions = [
            ModelDefinition(
                id: "model_kimi_k3", displayName: "Kimi K3", modelLabel: "kimi-k3",
                driverId: "kimi", role: .both, origin: .builtIn, defaultEnabled: true,
                capabilities: ModelCapabilities()),
        ]
        let modelList = ModelListProjector.build(
            registry: registry, definitions: definitions, probeRecords: [record], now: now,
            diagnostics: [])
        let menu = MenuCatalog.project(
            modelEntries: modelList.models, detailed: true)
        let row = try! XCTUnwrap(menu.models.first { $0.id == "model_kimi_k3" })
        XCTAssertEqual(row.freshness.checkedAt, record.lastProbeAt)
        XCTAssertEqual(row.freshness.ageMinutes, 38 * 60)
        XCTAssertTrue(row.freshness.stale)
        XCTAssertEqual(row.freshness.evidenceSource, "driver")
        XCTAssertEqual(row.freshness.nextAction.command, "alln doctor --full --agent kimi")
    }

    /// Control inside the menu surface: a never-probed model's row still
    /// reports `checkedAt: nil` after the hand-off through `MenuCatalog`,
    /// not a timestamp fabricated somewhere along the way.
    func testMenuModelRowForNeverProbedDriverReportsNullCheckedAt() {
        let registry = DriverRegistry([
            DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
        ])
        let definitions = [
            ModelDefinition(
                id: "model_oc", displayName: "OC", modelLabel: "oc",
                driverId: "opencode", role: .both, origin: .builtIn, defaultEnabled: true,
                capabilities: ModelCapabilities()),
        ]
        let modelList = ModelListProjector.build(
            registry: registry, definitions: definitions, probeRecords: [], now: now,
            diagnostics: [])
        let menu = MenuCatalog.project(
            modelEntries: modelList.models, detailed: true)
        let row = try! XCTUnwrap(menu.models.first { $0.id == "model_oc" })
        XCTAssertNil(row.freshness.checkedAt)
        XCTAssertNil(row.freshness.ageMinutes)
        XCTAssertTrue(row.freshness.stale)
    }
}
