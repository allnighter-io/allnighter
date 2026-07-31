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
public enum AllnighterVersionIdentity {
    public static let binaryVersion = "0.11.1"
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

    public init(
        schemaVersion: Int = 1,
        binaryVersion: String,
        contractVersion: String = ContractRegistry.contractVersion,
        contractHash: String = ContractRegistry.contractHash(),
        gitSha: String? = nil,
        buildTime: String? = nil,
        binaryPath: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
        self.contractHash = contractHash
        self.gitSha = gitSha
        self.buildTime = buildTime
        self.binaryPath = binaryPath
    }
}
