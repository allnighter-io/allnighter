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
///
/// **0.12.3 → 0.12.4 (shadow-mode pane reader, `Handover_Capacity_2026-08-08.md`
/// §5).** `contractVersion` additive minor (9.11.0 → 9.12.0): `capacity`
/// gains developer-only `--shadow-pane-reader` `FlagSpec`. Diagnostic opt-in
/// only — never reachable from `alln serve`'s scheduler or the Mac resident's
/// periodic refresh, never changes a published capacity value. Not a major
/// cut, standard +0.0.1.
///
/// **0.12.4 → 0.12.5 (PF-S03b, `docs/phases/Probe_Freshness.md`).**
/// `contractVersion` additive minor (9.12.0 → 9.13.0): `ToolProbeRecord`
/// splits its one timestamp into `lastDetectedAt` (cheap presence, any check)
/// and a narrowed `lastProbeAt` (capability evidence only — a real smoke or a
/// real completed run). `RunService`'s settlement now writes `lastProbeAt` too
/// (previously the probe path was the only writer), using the same
/// `WorkerAnswerErrorKind` taxonomy: success confirms, `missingCLI`/
/// `authRequired` record a negative, everything else writes nothing.
/// `freshness` (menu/drivers/models) gains `detectedAt` and `evidenceSource`
/// gains `"run"`. Disclosure only — no verdict/status/blockedReason changed;
/// an old record with no `lastDetectedAt` reports capability unknown until
/// its first new-style write. Not a major cut, standard +0.0.1.
///
/// **0.12.5 → 0.12.6 (PF-S04, Menu Freshness Normalization).**
/// `contractVersion` additive minor (9.13.0 → 9.14.0): PF-S01 gave every
/// driver AND model row a full `freshness` object, but a model is never
/// independently probed — every model row was copying its driver's object
/// verbatim (measured: 29 objects, 9 distinct values, 4,130 of 6,325 added
/// bytes were exact duplicates, ~2% headroom left against the 30 KiB `menu`
/// budget). The only thing an agent does with freshness on a model row is
/// decide whether to trust the readiness verdict — one boolean. `menu` and
/// `models` model rows now carry only `stale`; the full disclosure
/// (`checkedAt`/`ageMinutes`/`detectedAt`/`evidenceSource`/`nextAction`)
/// stays exactly where it already lived in full on `alln drivers --json`,
/// reachable via the model row's existing `driverId` — no new pointer field,
/// no second call, nothing removed from the payload. Driver rows are
/// unchanged. Normalization, not the field-dropping
/// `Menu_Envelope_Compression` rejected. Not a major cut, standard +0.0.1.
///
/// **0.12.6 → 1.0.0 (launch).** Public semver for the shipped CLI — no
/// `contractVersion` major cut in this batch. The 0.x train was pre-launch
/// dogfood; 1.0.0 is the first customer-facing release identity.
///
/// **1.0.0 → 1.0.1 (FCS-S02).** `contractVersion` additive minor (9.16.0 →
/// 9.17.0): optional `MenuJSON.benchTally` with agent `nextAction` when the
/// bench was never scanned. Standard +0.0.1 batch bump.
///
/// **1.1.0 → 1.1.1 (local Ollama readiness).** `contractVersion` additive
/// minor (10.0.0 → 10.1.0): local seat `readiness` is `Available` |
/// `Unavailable` per seat. Idle/Busy cut — Busy inverted the word. Not a
/// major cut, standard +0.0.1.
///
/// **1.1.1 → 1.1.2 (trial / Stripe Checkout).** `contractVersion` additive
/// minor (10.1.0 → 10.2.0): `alln billing` / `billing checkout`, optional
/// `MenuJSON.entitlement`, error `ENTITLEMENT_LIMIT`. Not a major cut.
/// **1.1.2 → 1.1.3 (Keep going).** Same contract 10.3.0: Mac overlay + Settings
/// › Plan + CLI `tellHuman` so agents quote the human on the 4th run.
///
/// **1.1.3 → 1.1.4 (Documents TCC).** Same contract 10.3.0: `get-alln.sh`
/// `cd "$HOME"` before any alln exec; Find my team uses non-interactive
/// login (`-lc`) + ProbeScratch CWD so signed cold install and DMG first
/// scan do not prompt for Documents.
///
/// **1.1.4 → 1.1.5 (setup + probe truth + Ask AI).** Same contract 10.3.0:
/// republish after 1.1.4 shipped with a stale binary (gitSha behind HEAD). Park
/// unsigned-in CLIs; AGY smoke uses Gemini Flash not Opus; OpenCode smoke
/// uses Go flash on Go-only hosts; compact AGY quota resets classify as
/// rateLimited not probeFailed. Mac title-bar Ask AI (Auto + inward preamble);
/// undocumented `alln dev ask-ai` is not a customer surface.
///
/// **1.1.5 → 1.1.6 (chrome catalog).** `contractVersion` additive minor
/// (10.3.0 → 10.4.0): `alln chrome --json` projects Mac owner-action rows from
/// the same labels the app draws. Ask AI uses it for "where is the button?"
/// — not doctor, not a help article.
///
/// **1.1.6 → 1.1.7 (person hatch).** `contractVersion` additive minor
/// (10.4.0 → 10.5.0): `VersionJSON.tellHuman` is the support@ hatch on
/// `alln version`. Failed CLI JSON (`emitFailure`) falls back to
/// `emailSupport` nextAction when ErrorDiscovery has none. Doctor unchanged.
///
/// **1.1.7 → 1.1.8 (feedback postcard).** `contractVersion` additive minor
/// (10.5.0 → 10.6.0): `alln feedback "<msg>"` sends quoted text + CLI version
/// + OS only. `--dry-run --json` is the free twin. Failures fall back to the
/// hatch. Doctor unchanged.
///
/// **1.1.8 → 1.1.9 (CLI payload + relocate-proof).** Naked `alln-macos-universal`
/// crashed on every machine except the builder: the SwiftPM resource-bundle
/// accessor needs `AgentOS_AgentOSCLI.bundle` beside the executable, and the
/// ship `version` check was a false green against the compile-time fallback
/// path. Payload is now `alln-macos-universal.tar.gz` (binary + bundles).
/// `scripts/ship-cli.sh` is the one ship path; relocate-proof hides build
/// scratches before `version`.
///
/// **1.1.9 → 1.1.10 (bare `alln` Documents TCC).** `ProtectedCWDEscape.adoptNeutral`
/// `chdir`s to ProbeScratch without `getcwd` for every command that does not
/// need the caller's repo cwd. `escapeIfNeeded` still getcwd's first — that
/// read is the prompt. Universal ship scratch moved out of the Documents
/// checkout so the resource-bundle accessor cannot bake a protected-folder
/// path into the binary. Same contract 10.6.0.
///
/// **1.1.10 → 1.1.11 (`alln serve` resource-accessor TCC).** The 1.1.10 chdir
/// and Library scratch did not stop the LaunchAgent: `alln serve` loads the
/// catalog via the SwiftPM accessor, which stats a compile-time path when
/// `Bundle(path: sidecar)` is nil (SPM sidecars have no Info.plist). Relocate
/// proof now runs `alln menu --json` (catalog load), not `version`. Production
/// loaders read sidecar files. OpenCode allow-roots come from the run root /
/// held write locks, not a hardcoded GitHub path. Same contract 10.6.0.
///
/// **1.1.11 → 1.1.12 (PATH argv[0] catalog trap + install receipt).** Bare
/// `alln` on PATH SIGTRAPped in `ModelCatalog.bundledAuthority`: 1.1.11 located
/// sidecars from argv[0] after `adoptNeutral` chdir'd to ProbeScratch.
/// `_NSGetExecutablePath` + symlink resolve is the lookup; relocate-proof
/// invokes a bare name on PATH. Human `install-cli` / `get-alln.sh` paint a
/// TTY receipt. Same contract 10.6.0.
///
/// **1.1.12 → 1.1.13 (bare TTY greeting).** Bare TTY `alln` prints a teaching
/// card; `--help` / non-TTY stay the command catalog. Human install receipt
/// next step is `alln` on a TTY, `alln menu --json` otherwise. Same contract
/// 10.6.0.
public enum AllnighterVersionIdentity {
    public static let binaryVersion = "1.1.13"
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
    /// Person hatch. Quote to the human; never a recovery command.
    public var tellHuman: String

    /// Human `alln version` identity. Contract hash / git live in `--json`.
    public func humanLine(color: Bool = false) -> String {
        let title = CLIPaint.accent("alln \(binaryVersion)", color: color)
        let hatch = CLIPaint.muted(tellHuman, color: color)
        return "\(title)\n\(hatch)"
    }

    public init(
        schemaVersion: Int = 1,
        binaryVersion: String,
        contractVersion: String = ContractRegistry.contractVersion,
        contractHash: String = ContractRegistry.contractHash(),
        gitSha: String? = nil,
        buildTime: String? = nil,
        binaryPath: String? = nil,
        update: ReleaseUpdateInfo? = nil,
        tellHuman: String = SupportHatch.tellHuman
    ) {
        self.schemaVersion = schemaVersion
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
        self.contractHash = contractHash
        self.gitSha = gitSha
        self.buildTime = buildTime
        self.binaryPath = binaryPath
        self.update = update
        self.tellHuman = tellHuman
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, binaryVersion, contractVersion, contractHash
        case gitSha, buildTime, binaryPath, update, tellHuman
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        binaryVersion = try c.decode(String.self, forKey: .binaryVersion)
        contractVersion = try c.decode(String.self, forKey: .contractVersion)
        contractHash = try c.decode(String.self, forKey: .contractHash)
        gitSha = try c.decodeIfPresent(String.self, forKey: .gitSha)
        buildTime = try c.decodeIfPresent(String.self, forKey: .buildTime)
        binaryPath = try c.decodeIfPresent(String.self, forKey: .binaryPath)
        update = try c.decodeIfPresent(ReleaseUpdateInfo.self, forKey: .update)
        tellHuman = try c.decodeIfPresent(String.self, forKey: .tellHuman) ?? SupportHatch.tellHuman
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
        try container.encode(tellHuman, forKey: .tellHuman)
    }
}
