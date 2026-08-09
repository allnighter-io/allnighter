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

    /// A NEW-STYLE, genuinely-confirmed record: `lastDetectedAt` set alongside
    /// `lastProbeAt` (Probe_Freshness Option A) so it discloses as real
    /// capability evidence, not the "predates the split" migration case.
    private func freshRecord(driverId: String, ageSeconds: TimeInterval) -> ToolProbeRecord {
        let at = now.addingTimeInterval(-ageSeconds)
        return ToolProbeRecord(
            driverId: driverId, status: .ready(version: "1.0"),
            lastProbeAt: at, lastDetectedAt: at)
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
    /// itself were probed — `ProbeFreshnessDisclosure.forModel`'s
    /// `evidenceSource: "driver"` makes the inheritance explicit rather than
    /// implied. PF-S04: the projected ROW itself carries only the decision
    /// bit (`stale`) inline; the full disclosure this test still exercises
    /// directly now lives on the owning driver row (`alln drivers --json`),
    /// reachable via this row's own `driverId`.
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
        let disclosure = ProbeFreshnessDisclosure.forModel(record, driverId: "kimi", now: now)
        XCTAssertEqual(disclosure.checkedAt, record.lastProbeAt)
        XCTAssertEqual(disclosure.ageMinutes, 38 * 60)
        XCTAssertTrue(disclosure.stale)
        XCTAssertEqual(disclosure.evidenceSource, "driver", "a model is never independently probed")
        XCTAssertEqual(disclosure.nextAction.command, "alln doctor --full --agent kimi")
        XCTAssertEqual(row.stale, disclosure.stale, "the row's inline bit must match the full disclosure")
        XCTAssertEqual(row.driverId, "kimi", "the full detail is reachable via this existing field")
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
        let disclosure = ProbeFreshnessDisclosure.forModel(nil, driverId: "opencode", now: now)
        XCTAssertNil(disclosure.checkedAt)
        XCTAssertNil(disclosure.ageMinutes)
        XCTAssertTrue(disclosure.stale)
        XCTAssertEqual(disclosure.evidenceSource, "driver")
        XCTAssertTrue(row.stale)
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
        let disclosure = ProbeFreshnessDisclosure.forModel(record, driverId: "grok", now: now)
        XCTAssertEqual(disclosure.ageMinutes, 5)
        XCTAssertFalse(disclosure.stale)
        XCTAssertFalse(row.stale)
    }

    // MARK: - alln menu --json (Tier-1 front door)

    /// The menu is the primary agent front door named by the Works Test.
    /// `MenuCatalog.project` is fed `ModelListJSON.Entry` rows built by
    /// `ModelListProjector`, so PF-S04's `stale` bit must survive that
    /// hand-off into `MenuJSON.Model.stale` unchanged — never re-derived,
    /// never dropped.
    func testMenuModelRowCarriesTheSameStaleBitAsTheModelListEntry() {
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
        let entry = try! XCTUnwrap(modelList.models.first { $0.id == "model_kimi_k3" })
        let row = try! XCTUnwrap(menu.models.first { $0.id == "model_kimi_k3" })
        XCTAssertTrue(entry.stale)
        XCTAssertEqual(row.stale, entry.stale)
    }

    /// Control inside the menu surface: a never-probed model's row still
    /// reports `stale: true` after the hand-off through `MenuCatalog`, not a
    /// fabricated positive slipped in somewhere along the way.
    func testMenuModelRowForNeverProbedDriverIsStale() {
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
        XCTAssertTrue(row.stale)
    }

    // MARK: - PF-S04 — model rows normalize `freshness` down to `stale`

    /// The wire proof the slice exists for: a model row's JSON must carry a
    /// plain `stale` boolean, and must NEVER carry a `freshness` key — the
    /// duplicated object this slice removes. Against pre-fix code this fails
    /// because `models[n]` still has a `freshness` object instead of `stale`.
    func testModelListRowEncodesStaleNotFreshnessObject() throws {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let record = freshRecord(driverId: "kimi", ageSeconds: 300)
        let definitions = [
            ModelDefinition(
                id: "model_kimi_k3", displayName: "Kimi K3", modelLabel: "kimi-k3",
                driverId: "kimi", role: .both, origin: .builtIn, defaultEnabled: true,
                capabilities: ModelCapabilities()),
        ]
        let list = ModelListProjector.build(
            registry: registry, definitions: definitions, probeRecords: [record], now: now,
            diagnostics: [])
        let data = try CoreJSON.encode(list)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let models = try XCTUnwrap(obj["models"] as? [[String: Any]])
        let row = try XCTUnwrap(models.first { $0["id"] as? String == "model_kimi_k3" })
        XCTAssertTrue(row["stale"] is Bool, "model row must carry a plain stale boolean")
        XCTAssertNil(row["freshness"], "model row must never carry the driver's full freshness object")
    }

    /// Same wire proof on the menu (Tier-1 front door) surface — the row this
    /// slice was actually measured against.
    func testMenuModelRowEncodesStaleNotFreshnessObject() throws {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let record = freshRecord(driverId: "kimi", ageSeconds: 300)
        let definitions = [
            ModelDefinition(
                id: "model_kimi_k3", displayName: "Kimi K3", modelLabel: "kimi-k3",
                driverId: "kimi", role: .both, origin: .builtIn, defaultEnabled: true,
                capabilities: ModelCapabilities()),
        ]
        let modelList = ModelListProjector.build(
            registry: registry, definitions: definitions, probeRecords: [record], now: now,
            diagnostics: [])
        let menu = MenuCatalog.project(modelEntries: modelList.models, detailed: true)
        let data = try CoreJSON.encode(menu)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let models = try XCTUnwrap(obj["models"] as? [[String: Any]])
        let row = try XCTUnwrap(models.first { $0["id"] as? String == "model_kimi_k3" })
        XCTAssertTrue(row["stale"] is Bool, "menu model row must carry a plain stale boolean")
        XCTAssertNil(row["freshness"], "menu model row must never carry the driver's full freshness object")
    }

    /// The other half of the same proof: the DRIVER row is untouched by this
    /// slice — it is the single remaining home for the full disclosure, so
    /// it must still carry every field, including the literal-null
    /// `checkedAt` a never-probed driver reports.
    func testDriverRowStillEncodesTheFullFreshnessObject() throws {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let record = freshRecord(driverId: "kimi", ageSeconds: 300)
        let list = DriverListProjector.build(
            registry: registry, probeRecords: [record], now: now, models: [], parkedDriverIds: [])
        let data = try CoreJSON.encode(list)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let drivers = try XCTUnwrap(obj["drivers"] as? [[String: Any]])
        let row = try XCTUnwrap(drivers.first { $0["driverId"] as? String == "kimi" })
        let freshness = try XCTUnwrap(row["freshness"] as? [String: Any])
        for key in ["checkedAt", "ageMinutes", "detectedAt", "stale", "evidenceSource", "nextAction"] {
            XCTAssertTrue(freshness.keys.contains(key), "driver row must still carry \(key)")
        }
    }

    // MARK: - Three states (Probe_Freshness Option A — lastDetectedAt split)

    /// Migration rule: a record written before this split has no
    /// `lastDetectedAt` at all. Its `lastProbeAt` may have been stamped by a
    /// non-smoke check (the exact overclaim this packet exists to stop), so a
    /// reader must not trust it as capability evidence — `checkedAt` reports
    /// `nil` (unknown) even though the record's status is `.ready` and its
    /// raw `lastProbeAt` looks perfectly fresh. `detectedAt` still surfaces
    /// that same timestamp, reinterpreted as detection-only evidence.
    func testOldRecordWithNoLastDetectedAtReportsCapabilityUnknown() {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let record = ToolProbeRecord(
            driverId: "kimi", status: .ready(version: "1.0"),
            lastProbeAt: now.addingTimeInterval(-300))
        XCTAssertNil(record.lastDetectedAt, "fixture must be the pre-split shape")
        let list = DriverListProjector.build(
            registry: registry, probeRecords: [record], now: now, models: [], parkedDriverIds: [])
        let row = try! XCTUnwrap(list.drivers.first)
        XCTAssertNil(row.freshness.checkedAt, "an old record's capability is unknown, not confirmed")
        XCTAssertNil(row.freshness.ageMinutes)
        XCTAssertTrue(row.freshness.stale)
        XCTAssertEqual(row.freshness.detectedAt, record.lastProbeAt,
                        "the old lastProbeAt is still honest detection evidence")
    }

    /// A new-style record whose status is `.installedNotProbed` — a cheap
    /// check ran (so `lastDetectedAt` is set) but no smoke ever did — is
    /// "detected, never exercised": `detectedAt` is real, `checkedAt` stays
    /// `nil`. This is the state that does not exist pre-split.
    func testDetectedButNeverExercisedReportsNullCheckedAtWithRealDetectedAt() {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let detectedAt = now.addingTimeInterval(-120)
        let record = ToolProbeRecord(
            driverId: "kimi", status: .installedNotProbed(version: "1.0"),
            invocation: .direct(path: "/usr/local/bin/kimi"), version: "1.0",
            lastProbeAt: detectedAt, lastDetectedAt: detectedAt)
        let list = DriverListProjector.build(
            registry: registry, probeRecords: [record], now: now, models: [], parkedDriverIds: [])
        let row = try! XCTUnwrap(list.drivers.first)
        XCTAssertNil(row.freshness.checkedAt, "never smoke-tested — capability genuinely unknown")
        XCTAssertNil(row.freshness.ageMinutes)
        XCTAssertTrue(row.freshness.stale)
        XCTAssertEqual(row.freshness.detectedAt, detectedAt, "presence WAS just checked")
    }

    /// A run-sourced write (`RunCapabilityClock.resolvedBy`) must be labeled
    /// distinctly from an explicit probe — never presented as one or the
    /// other's evidence by accident.
    func testDriverRowFromARunReportsEvidenceSourceRun() {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let at = now.addingTimeInterval(-60)
        let record = ToolProbeRecord(
            driverId: "kimi", status: .ready(version: "1.0"),
            lastProbeAt: at, lastDetectedAt: at, resolvedBy: "RunService")
        let list = DriverListProjector.build(
            registry: registry, probeRecords: [record], now: now, models: [], parkedDriverIds: [])
        let row = try! XCTUnwrap(list.drivers.first)
        XCTAssertEqual(row.freshness.checkedAt, at)
        XCTAssertEqual(row.freshness.evidenceSource, "run")
    }

    /// A model row inherits run-sourced evidence but never re-labels it as
    /// its OWN probe — `ProbeFreshnessDisclosure.forModel`'s `evidenceSource`
    /// stays `"driver"` regardless of what produced the underlying driver
    /// record. PF-S04: the projected row itself only carries `stale`; the
    /// labeling this test guards lives on the full disclosure, still
    /// exercised directly here.
    func testModelRowFromARunStillReportsEvidenceSourceDriver() {
        let registry = DriverRegistry([
            DriverManifest(id: "kimi", displayName: "Kimi", kind: .headlessCLI),
        ])
        let at = now.addingTimeInterval(-60)
        let record = ToolProbeRecord(
            driverId: "kimi", status: .ready(version: "1.0"),
            lastProbeAt: at, lastDetectedAt: at, resolvedBy: "RunService")
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
        let disclosure = ProbeFreshnessDisclosure.forModel(record, driverId: "kimi", now: now)
        XCTAssertEqual(disclosure.checkedAt, at)
        XCTAssertEqual(disclosure.evidenceSource, "driver")
        XCTAssertEqual(row.stale, disclosure.stale)
    }

    /// A source that has never been detected at all (no record) reports
    /// BOTH clocks null — "not detected", the free-est of the three states.
    func testNeverDetectedDriverReportsBothClocksNull() {
        let registry = DriverRegistry([
            DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
        ])
        let list = DriverListProjector.build(
            registry: registry, probeRecords: [], now: now, models: [], parkedDriverIds: [])
        let row = try! XCTUnwrap(list.drivers.first)
        XCTAssertNil(row.freshness.checkedAt)
        XCTAssertNil(row.freshness.detectedAt)
    }
}
