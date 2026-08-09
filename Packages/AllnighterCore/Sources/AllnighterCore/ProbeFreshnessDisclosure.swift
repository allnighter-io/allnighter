import Foundation
import AgentOSCLI

/// PF-S01 — every driver/model row discloses how old its evidence is.
///
/// PF-S00 (`ProbeFreshnessGate`) governs whether a verdict may be ASSERTED: an
/// expired or inferred negative decays to unknown, never to a stronger claim.
/// This is a different, narrower question — given whatever verdict a row
/// already carries, how old is the evidence behind it, and what command
/// actually refreshes it. Disclosure only. Nothing here changes a `status`, a
/// `ready`, or a `blockedReason` — see `Probe_Freshness.md` §PF-S01: "The
/// 'no negative verdict from a stale record' assertion belongs to PF-S00's
/// gate, not here — this slice adds disclosure only."
///
/// Two rulings from the packet bind this shape:
///
/// 1. `checkedAt` is `null` for a never-probed row — not epoch zero, not
///    `now`, not omitted. A fabricated timestamp on a row nobody ever checked
///    is exactly the lie this packet exists to remove.
/// 2. A model is never independently smoke-probed; it inherits its owning
///    driver's evidence, and the payload must say so rather than silently
///    presenting the driver's `checkedAt` as if the model itself were
///    checked — `evidenceSource` carries that disclosure.
public struct ProbeFreshnessJSON: Codable, Sendable, Equatable {
    /// When the evidence behind this row was taken. `null` when the source —
    /// this driver, or (for a model row) its owning driver — has never been
    /// probed at all.
    public var checkedAt: Date?
    /// Minutes between `checkedAt` and read time. `null` exactly when
    /// `checkedAt` is `null`.
    public var ageMinutes: Int?
    /// True when there is no evidence at all, or the evidence is older than
    /// `ProbeFreshnessGate.gateInterval` (or its own stated retry window).
    /// Disclosure only — a stale `ready` still reads `ready`; PF-S00 alone
    /// decides whether a stale NEGATIVE may still be asserted.
    public var stale: Bool
    /// `"probe"` — this row's own probe record is the evidence (driver rows).
    /// `"driver"` — inherited from the owning driver's probe record; the row
    /// itself was never independently checked (model rows, always).
    public var evidenceSource: String
    /// The command that actually refreshes this evidence.
    public var nextAction: AgentSurfaceNextAction

    public init(
        checkedAt: Date?,
        ageMinutes: Int?,
        stale: Bool,
        evidenceSource: String,
        nextAction: AgentSurfaceNextAction
    ) {
        self.checkedAt = checkedAt
        self.ageMinutes = ageMinutes
        self.stale = stale
        self.evidenceSource = evidenceSource
        self.nextAction = nextAction
    }

    private enum CodingKeys: String, CodingKey {
        case checkedAt, ageMinutes, stale, evidenceSource, nextAction
    }

    /// Swift's synthesized `Encodable` calls `encodeIfPresent` for `Optional`
    /// stored properties, which OMITS the key entirely when nil — verified
    /// against this file's own live output. That is exactly wrong here: the
    /// packet's ruling is "`checkedAt` is `null` for a never-probed row — not
    /// epoch zero, not `now`, not omitted." An omitted key and an absent
    /// `null` key look identical to a careless reader but are not the same
    /// disclosure, so `checkedAt`/`ageMinutes` are force-written as explicit
    /// `null` here. Decoding stays synthesized — a matching `CodingKeys` is
    /// enough for that half, and `decodeIfPresent`-style leniency is fine on
    /// the read side.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let checkedAt { try c.encode(checkedAt, forKey: .checkedAt) }
        else { try c.encodeNil(forKey: .checkedAt) }
        if let ageMinutes { try c.encode(ageMinutes, forKey: .ageMinutes) }
        else { try c.encodeNil(forKey: .ageMinutes) }
        try c.encode(stale, forKey: .stale)
        try c.encode(evidenceSource, forKey: .evidenceSource)
        try c.encode(nextAction, forKey: .nextAction)
    }
}

/// Builds `ProbeFreshnessJSON` for a driver row (its own evidence) or a model
/// row (inherited from its owning driver). Read-time only, same law as
/// `ProbeFreshnessGate` — never touches the stored record, and needs the
/// record's original `lastProbeAt` to disclose age honestly.
public enum ProbeFreshnessDisclosure {
    /// Fallback for a driver row built with no probe record and no driver id
    /// in hand at all. Every real call site computes its own; this exists so
    /// an unrelated call site adding a field doesn't have to. The honest "we
    /// don't know" state — not a fabricated timestamp with a guessed
    /// positive spin.
    public static let unknownDriver = ProbeFreshnessJSON(
        checkedAt: nil, ageMinutes: nil, stale: true,
        evidenceSource: "probe", nextAction: refreshAction(driverId: nil)
    )

    /// Same fallback, for a model row (e.g. `MenuCatalog`'s no-registry
    /// fallback catalog).
    public static let unknownModel = ProbeFreshnessJSON(
        checkedAt: nil, ageMinutes: nil, stale: true,
        evidenceSource: "driver", nextAction: refreshAction(driverId: nil)
    )

    /// The command that actually refreshes one driver's probe record.
    /// Verified live against `SourceProbeService.probe`: a single-manifest
    /// `--agent` request smokes and persists just that driver's record (and
    /// does so even when the driver is parked — `probeRecords` bypasses the
    /// park filter when exactly one manifest is named).
    public static func refreshAction(driverId: String?) -> AgentSurfaceNextAction {
        guard let driverId else {
            return AgentSurfaceNextAction(
                kind: "refreshProbe", label: "Re-probe sources",
                command: "alln doctor --full")
        }
        return AgentSurfaceNextAction(
            kind: "refreshProbe", label: "Re-probe \(driverId)",
            command: "alln doctor --full --agent \(driverId)")
    }

    /// A driver row: its own probe record is the evidence.
    public static func forDriver(
        _ record: ToolProbeRecord?, driverId: String, now: Date
    ) -> ProbeFreshnessJSON {
        build(record, driverId: driverId, now: now, evidenceSource: "probe")
    }

    /// A model row: never independently probed, so it always inherits its
    /// owning driver's evidence. `evidenceSource: "driver"` makes that
    /// inheritance explicit in the payload rather than leaving it implied.
    public static func forModel(
        _ record: ToolProbeRecord?, driverId: String, now: Date
    ) -> ProbeFreshnessJSON {
        build(record, driverId: driverId, now: now, evidenceSource: "driver")
    }

    private static func build(
        _ record: ToolProbeRecord?, driverId: String, now: Date, evidenceSource: String
    ) -> ProbeFreshnessJSON {
        guard let record else {
            return ProbeFreshnessJSON(
                checkedAt: nil, ageMinutes: nil, stale: true,
                evidenceSource: evidenceSource, nextAction: refreshAction(driverId: driverId))
        }
        let ageMinutes = max(0, Int(now.timeIntervalSince(record.lastProbeAt) / 60))
        return ProbeFreshnessJSON(
            checkedAt: record.lastProbeAt,
            ageMinutes: ageMinutes,
            stale: ProbeFreshnessGate.isExpired(record, now: now),
            evidenceSource: evidenceSource,
            nextAction: refreshAction(driverId: driverId)
        )
    }
}
