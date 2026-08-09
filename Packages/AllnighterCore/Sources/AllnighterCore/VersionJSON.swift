import Foundation

/// ADP-S05: single source of truth for the alln binary version. Everything
/// that discloses a version string for the binary itself — `AllnighterCLI.
/// binaryVersion`, the Codex `clientInfo` handshake, `doctor`, `version
/// --json` — projects this constant. Never hardcode a second semver literal
/// for a binary-version/clientInfo field; `VersionIdentityTests` gates it.
///
/// Bump rule (docs/phases/Agent_Dogfood_Papercuts.md §Version rule): patch
/// (+0.0.1) on every shipped batch of behavior/teaching changes; minor
/// (+0.1.0) only when `contractVersion` takes a major cut. Distinct from
/// `ContractRegistry.contractVersion`, which is schema-shape governed and
/// never substitutes for this.
///
/// **Release note — 0.10.7 → 0.11.0 (LVC-S05, `docs/phases/Loop_Verb_Cutover.md`).**
/// `contractVersion` took its major cut (6.13.0 → 7.0.0): `alln pair relay*` /
/// `alln pair pilot*` are retired in favor of one `alln loop` verb, and the
/// `PMMode` wire enum (`spawned|external`) is deleted — the chair is now an
/// occupant id (`caller` or an agent id). **Breaking, deliberate, unshimmed:**
/// on-disk `LoopState` carrying the old `"pmMode":"external"` will not
/// decode. Finish or `stop` every in-flight loop before upgrading past this
/// version — there is no compatibility shim, no dual-read, no migration. This
/// fails loud on purpose (pre-user, foundation-first); do not add one later.
/// **LVC-S09:** loop durable state directory moved `Relays/` → `Loops/` (`AllnighterPaths.loops`);
/// on-disk `relay.json` filenames unchanged. Existing state under `Relays/` is not migrated —
/// `alln loop list` warns when `Loops/` is missing but `Relays/` still exists.
///
/// **0.11.0 → 0.11.1 (QABC-S00e).** `contractVersion` takes an additive minor
/// bump (7.0.0 → 7.1.0): optional `MenuJSON.capacity` declared in
/// `menu.schema.json` / `menu-show.schema.json`. Not a major cut, so this is
/// the standard +0.0.1 batch bump.
///
/// **0.11.1 → 0.11.2 (OPC-S02).** `contractVersion` additive minor (7.2.0 →
/// 7.3.0): bootstrap `--host` closed domain gains `hermes` | `openclaw`.
///
/// **0.11.2 → 0.11.3 (OPC-S06).** `contractVersion` additive minor (7.3.0 →
/// 7.4.0): optional top-level `MenuJSON.update` / `VersionJSON.update` from the
/// shared release channel (`latest.json` + fail-open cache). Not a major cut.
///
/// **0.11.3 → 0.11.4 (OPC-S06b).** Mac About/status reads the same channel via
/// `ReleaseChannel.checkAppUpdate` / `announceApp` (appVersion + human notes).
/// No contract wire change.
///
/// **0.11.4 → 0.12.0 (ORS-S03e, `docs/phases/One_Run_Surface.md`).**
/// `contractVersion` took major cuts in this ship batch (7.x → 8.0.0 → 9.0.0,
/// then additive 9.1.0/9.2.0 for declared `alln loop` verbs + free-twin dry-runs): public `team status` /
/// `team result`, old waiter flags, and `audit.runJournalPath` are deleted;
/// one `alln show --json|--stream` surface owns single-run read + delivery.
/// One binary minor bump for the whole batch (+0.1.0 on contract major cut).
///
/// **0.12.0 → 0.12.1 (ORS-P2-NULL regen).** `contractVersion` additive minor
/// (9.2.0 → 9.3.0): Observation.required gains always-present nullable
/// `lastActivityAt`. Not a major cut, so standard +0.0.1 batch bump.
///
/// **0.12.2 → 0.12.3 (PF-S01, `docs/phases/Probe_Freshness.md`).**
/// `contractVersion` additive minor (9.10.0 → 9.11.0): `menu` / `drivers` /
/// `models` driver and model rows gain a `freshness` object — `checkedAt`
/// (null when never probed), `ageMinutes`, `stale`, `evidenceSource`
/// (`"probe"` for a driver's own record, `"driver"` for a model's inherited
/// one), and `nextAction` naming the refresh command. Disclosure only; no
/// verdict/status/blockedReason changes. Not a major cut, standard +0.0.1.
public enum AllnighterVersionIdentity {
    public static let binaryVersion = "0.12.3"
}

/// `alln version` / `alln --version` machine contract.
public struct VersionJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var binaryVersion: String
    public var contractVersion: String
    public var contractHash: String
    /// Short or full git SHA embedded at build time (`unknown` when unavailable).
    public var gitSha: String?
    /// UTC build timestamp (`YYYY-MM-DDTHH:MM:SSZ`), or `unknown`.
    public var buildTime: String?
    /// Absolute path of the running binary (AE-S08).
    public var binaryPath: String?
    /// OPC-S06 — same `ReleaseChannel` truth as `menu.update`. Omitted when nil.
    public var update: ReleaseUpdateInfo?

    public init(
        schemaVersion: Int = 1,
        binaryVersion: String,
        contractVersion: String = ContractRegistry.contractVersion,
        contractHash: String = ContractRegistry.contractHash(),
        gitSha: String? = nil,
        buildTime: String? = nil,
        binaryPath: String? = nil,
        update: ReleaseUpdateInfo? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
        self.contractHash = contractHash
        self.gitSha = gitSha
        self.buildTime = buildTime
        self.binaryPath = binaryPath
        self.update = update
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, binaryVersion, contractVersion, contractHash
        case gitSha, buildTime, binaryPath, update
    }

    /// Omit `update` when nil (never encode `"update": null`). Other optionals
    /// keep the historical synthesized-null behavior via encodeIfPresent so
    /// existing consumers still see the same keys when values exist.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(binaryVersion, forKey: .binaryVersion)
        try container.encode(contractVersion, forKey: .contractVersion)
        try container.encode(contractHash, forKey: .contractHash)
        try container.encodeIfPresent(gitSha, forKey: .gitSha)
        try container.encodeIfPresent(buildTime, forKey: .buildTime)
        try container.encodeIfPresent(binaryPath, forKey: .binaryPath)
        try container.encodeIfPresent(update, forKey: .update)
    }
}
