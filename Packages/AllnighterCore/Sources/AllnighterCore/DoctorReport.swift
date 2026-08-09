import Foundation

/// Builds a `DoctorResult` from detection records + bench + local-check facts
/// (docs/archive/phases/CLI_Implementation_Contract.md §Doctor Contract).
///
/// Pure and quota-aware: with `full == false` (the default `alln doctor`), the
/// smoke probe never ran, so auth/smoke/readiness are reported honestly as
/// `notChecked` with a next action pointing at `alln doctor --full` — never
/// inferred from the absence of a probe. With `full == true`, those checks
/// reflect the real probe outcome.
public enum DoctorReport {
    public struct Inputs: Sendable {
        public var binaryVersion: String
        public var contractVersion: String
        public var docsVersionMatchesBinary: Bool
        /// Running binary's embedded gitSha (AE-S08).
        public var binaryGitSha: String?
        /// Workspace HEAD gitSha when doctor runs inside a checkout (AE-S08).
        public var workspaceHeadSha: String?
        public var configDirWritable: Bool
        public var runsDirWritable: Bool
        public var pendingDirWritable: Bool
        /// Observed `alln serve` daemon state from `ServeDaemonProbe` when set.
        public var coordinator: DoctorResult.Coordinator?
        /// True when smoke probes ran (`--full`); false for the quota-free path.
        public var full: Bool
        /// Optional path to Cursor's global CLI config (`~/.cursor/cli-config.json`).
        /// Injectable for tests — never read the real user file from unit tests.
        /// `nil` → the shell-allowlist check reports `notChecked`.
        public var cursorCLIConfigURL: URL?
        /// Optional repo-scoped override (`.cursor/cli.json` near cwd). Injectable for tests.
        public var cursorProjectOverrideURL: URL?
        /// Resolved absolute path of the running `alln` binary. `nil` → `binary.onPath` is `notChecked`.
        public var runningBinaryPath: String?
        /// PATH used to resolve `alln`. `nil` → `binary.onPath` is `notChecked`.
        public var pathEnvironment: String?
        /// When set (via `alln doctor --pilot`), emits a `pilot` summary check.
        public var pilot: PilotContext?
        /// Optional teaching-snippet probe inputs (ONB-S01). `nil` → `teaching.installed`
        /// is `notChecked` (unit-test default). Live CLI passes home-derived targets.
        public var teachingInputs: [TeachingInstalledCheck.TargetInput]?
        /// OPC-S06 — same `ReleaseChannel` announcement as menu/version. `nil` means
        /// no newer release announced (or check disabled/failed); never remote notes.
        public var update: ReleaseUpdateInfo?

        public init(
            binaryVersion: String,
            contractVersion: String,
            docsVersionMatchesBinary: Bool = true,
            binaryGitSha: String? = nil,
            workspaceHeadSha: String? = nil,
            configDirWritable: Bool,
            runsDirWritable: Bool,
            pendingDirWritable: Bool = true,
            coordinator: DoctorResult.Coordinator? = nil,
            full: Bool,
            cursorCLIConfigURL: URL? = nil,
            cursorProjectOverrideURL: URL? = nil,
            runningBinaryPath: String? = nil,
            pathEnvironment: String? = nil,
            pilot: PilotContext? = nil,
            teachingInputs: [TeachingInstalledCheck.TargetInput]? = nil,
            update: ReleaseUpdateInfo? = nil
        ) {
            self.binaryVersion = binaryVersion
            self.contractVersion = contractVersion
            self.docsVersionMatchesBinary = docsVersionMatchesBinary
            self.binaryGitSha = binaryGitSha
            self.workspaceHeadSha = workspaceHeadSha
            self.configDirWritable = configDirWritable
            self.runsDirWritable = runsDirWritable
            self.pendingDirWritable = pendingDirWritable
            self.coordinator = coordinator
            self.full = full
            self.cursorCLIConfigURL = cursorCLIConfigURL
            self.cursorProjectOverrideURL = cursorProjectOverrideURL
            self.runningBinaryPath = runningBinaryPath
            self.pathEnvironment = pathEnvironment
            self.pilot = pilot
            self.teachingInputs = teachingInputs
            self.update = update
        }
    }

    /// Inputs for the `doctor.pilot` summary check (`Pilot_DX.md` §DX6).
    public struct PilotContext: Sendable, Equatable {
        public var projectLabel: String?
        public var devModelId: String?
        public var devWorkerLabel: String?
        public var driverInstalled: Bool
        /// `nil` on the quota-free path — readiness not smoke-probed.
        public var driverReady: Bool?

        public init(
            projectLabel: String? = nil,
            devModelId: String? = nil,
            devWorkerLabel: String? = nil,
            driverInstalled: Bool = false,
            driverReady: Bool? = nil
        ) {
            self.projectLabel = projectLabel
            self.devModelId = devModelId
            self.devWorkerLabel = devWorkerLabel
            self.driverInstalled = driverInstalled
            self.driverReady = driverReady
        }
    }

    private static let fullFix = "alln doctor --full"

    public static func build(models: [Model], manifests: [DriverManifest], records: [ToolProbeRecord], inputs: Inputs) -> DoctorResult {
        func sourceName(_ id: String) -> String { manifests.first { $0.id == id }?.displayName ?? id }
        let sourcesLoaded = !manifests.isEmpty
        let recByDriver = Dictionary(records.map { ($0.driverId, $0) }, uniquingKeysWith: { a, _ in a })

        var checks: [DoctorResult.Check] = [
            .init(name: "binaryVersion", status: .ok, detail: "alln \(inputs.binaryVersion)"),
            .init(name: "docsVersion",
                  status: inputs.docsVersionMatchesBinary ? .ok : .degraded,
                  detail: inputs.docsVersionMatchesBinary ? "generated docs match the contract registry" : "generated docs drift from the registry",
                  fixCommand: inputs.docsVersionMatchesBinary ? nil : "alln dev export-contracts"),
            binaryStaleCheck(inputs),
            updateCheck(inputs.update),
            .init(name: "configDir",
                  status: inputs.configDirWritable ? .ok : .critical,
                  detail: inputs.configDirWritable ? "config dir writable" : "config dir missing or not writable",
                  requiresManual: !inputs.configDirWritable),
            .init(name: "runsDir",
                  status: inputs.runsDirWritable ? .ok : .critical,
                  detail: inputs.runsDirWritable ? "run journal dir writable" : "run journal dir missing or not writable",
                  requiresManual: !inputs.runsDirWritable),
            .init(name: "sources",
                  status: sourcesLoaded ? .ok : .critical,
                  detail: sourcesLoaded ? "\(manifests.count) source manifests loaded" : "no source manifests loaded"),
        ]

        // Per-source checks from detection records.
        for r in records.sorted(by: { $0.driverId < $1.driverId }) {
            let name = sourceName(r.driverId)
            let manifest = manifests.first { $0.id == r.driverId }
            checks.append(installedCheck(r, name: name))
            checks.append(authCheck(r, name: name, full: inputs.full))
            if let trust = manifest?.setup?.headlessTrust, trust.required {
                checks.append(headlessTrustCheck(r.driverId, trust: trust))
            }
        }

        // Cursor shell allowlist — read-only vendor config; never mutated.
        let shellAllowlist = CursorShellAllowlist.check(
            configURL: inputs.cursorCLIConfigURL,
            projectOverrideURL: inputs.cursorProjectOverrideURL
        )
        checks.append(shellAllowlist)

        let binaryOnPath = BinaryOnPath.check(
            runningBinary: inputs.runningBinaryPath,
            pathEnvironment: inputs.pathEnvironment
        )
        checks.append(binaryOnPath)

        checks.append(TeachingInstalledCheck.check(inputs: inputs.teachingInputs))

        // Bench-readiness aggregate.
        if inputs.full {
            let ready = records.filter { $0.status.isSmokeReady }.count
            checks.append(.init(name: "benchReadyCount",
                                status: ready > 0 ? .ok : .critical,
                                detail: "\(ready) model\(ready == 1 ? "" : "s") ready",
                                requiresManual: ready == 0))
        } else {
            checks.append(.init(name: "benchReadyCount", status: .notChecked,
                                detail: "model readiness not checked (no smoke probe)", fixCommand: fullFix))
        }

        checks.append(.init(name: "defaultTeamValid",
                            status: models.isEmpty ? .critical : .ok,
                            detail: models.isEmpty ? "no models configured" : "\(models.count) models configured"))
        checks.append(planWriterCheck(models: models, recByDriver: recByDriver, full: inputs.full))
        checks.append(journalIncrementalCheck(inputs.runsDirWritable))
        checks.append(journalOrphanCheck(inputs.runsDirWritable))
        checks.append(pendingReadableCheck(inputs.pendingDirWritable))
        checks.append(pendingWritableCheck(inputs.pendingDirWritable))
        let coordinator = inputs.coordinator ?? DoctorResult.Coordinator(
            state: .foregroundOnly,
            detail: "foreground CLI only; background scheduler not running"
        )
        checks.append(coordinatorCheck(coordinator))
        checks.append(serveLaunchAgentCheck(coordinator.launchAgent))
        if let pilot = inputs.pilot {
            checks.append(pilotCheck(pilot, inputs: inputs))
        }

        let modelInfos = models.map { m -> TeamRunJSON.ModelInfo in
            let status: TeamRunJSON.ModelStatus
            if inputs.full {
                status = (recByDriver[m.driverId]?.status.isSmokeReady ?? false) ? .ready : .unavailable
            } else {
                status = .unknown
            }
            return TeamRunJSON.ModelInfo(id: m.id, displayName: m.displayName, sourceId: m.driverId, sourceName: sourceName(m.driverId), status: status)
        }

        var counsel: String?
        var nextActions: [AgentSurfaceNextAction] = []
        if !inputs.configDirWritable {
            let frontDoor = AgentFrontDoor.missingConfigCounsel()
            counsel = frontDoor.counsel
            nextActions = frontDoor.nextActions
        }

        return DoctorResult(
            status: overallStatus(
                records: records,
                sourcesLoaded: sourcesLoaded,
                inputs: inputs,
                shellAllowlistRestrictive: shellAllowlist.status == .degraded,
                binaryOffPath: binaryOnPath.status == .degraded
            ),
            binaryVersion: inputs.binaryVersion,
            contractVersion: inputs.contractVersion,
            docsVersionMatchesBinary: inputs.docsVersionMatchesBinary,
            checks: checks,
            fixes: [],
            models: modelInfos,
            coordinator: coordinator,
            counsel: counsel,
            nextActions: nextActions
        )
    }

    // MARK: - Per-check helpers

    private static func binaryStaleCheck(_ inputs: Inputs) -> DoctorResult.Check {
        guard let binary = inputs.binaryGitSha, !binary.isEmpty, binary != "unknown",
              let head = inputs.workspaceHeadSha, !head.isEmpty else {
            return .init(name: "BINARY_STALE", status: .notChecked,
                         detail: "no checkout identity was supplied — coordinator identity is checked independently")
        }
        let binShort = String(binary.prefix(12))
        let headShort = String(head.prefix(12))
        if binary.hasPrefix(headShort) || head.hasPrefix(binShort) || binary == head {
            return .init(name: "BINARY_STALE", status: .ok,
                         detail: "on-PATH binary gitSha matches workspace HEAD (\(binShort))")
        }
        return .init(
            name: "BINARY_STALE",
            status: .critical,
            detail: "on-PATH binary gitSha \(binShort) ≠ workspace HEAD \(headShort)",
            fixCommand: "swift build --package-path Packages/AllnighterCore && alln install-cli",
            requiresManual: false
        )
    }

    /// OPC-S06 — projects the same `ReleaseChannel` truth as menu/version.
    /// `fixCommand` is always the compiled-in one-liner (never remote).
    private static func updateCheck(_ update: ReleaseUpdateInfo?) -> DoctorResult.Check {
        guard let update else {
            return .init(
                name: "release.update",
                status: .ok,
                detail: "no newer release announced"
            )
        }
        return .init(
            name: "release.update",
            status: .degraded,
            detail: "alln \(update.current) → \(update.latest) available",
            fixCommand: ReleaseChannel.installCommand,
            requiresManual: true
        )
    }

    private static func installedCheck(_ r: ToolProbeRecord, name: String) -> DoctorResult.Check {
        switch r.status {
        case .ready, .installedNotProbed, .installedNotSignedIn, .probeFailed, .rateLimited:
            // rateLimited = healthy install + smoke hit a vendor quota wall (not missing).
            return .init(name: "source.\(r.driverId).installed", status: .ok, detail: "\(name) found\(r.version.map { " (\($0))" } ?? "")")
        case .shimmedNeedsConfirm:
            return .init(name: "source.\(r.driverId).installed", status: .degraded, detail: "\(name) needs a one-click path confirmation", requiresManual: true)
        case .notInstalled:
            return .init(name: "source.\(r.driverId).installed", status: .degraded, detail: "\(name) not found on PATH or known paths", requiresManual: true)
        }
    }

    private static func authCheck(_ r: ToolProbeRecord, name: String, full: Bool) -> DoctorResult.Check {
        let key = "source.\(r.driverId).auth"
        guard full else {
            return .init(name: key, status: .notChecked, detail: "auth not checked without --full", fixCommand: fullFix)
        }
        switch r.status {
        case .ready:
            return .init(name: key, status: .ok, detail: "\(name) authenticated")
        case .installedNotSignedIn(let flow):
            return .init(name: key, status: .degraded, detail: "\(name) is not signed in. \(flow.instructions)", fixCommand: flow.interactiveCommand, requiresManual: true)
        case .rateLimited(let observation):
            // Temporarily unavailable (quota/rate wall) — not "broken auth".
            return .init(
                name: key,
                status: .degraded,
                detail: "\(name) \(rateLimitedDetail(observation: observation))",
                requiresManual: true
            )
        case .probeFailed(let reason):
            let lower = reason.lowercased()
            if lower.contains("secitemcopymatching failed") {
                return .init(
                    name: key, status: .degraded,
                    detail: "\(name) Keychain auth unavailable (\(reason)). Open Cursor once, run `agent login`, then `alln doctor --full`.",
                    fixCommand: "agent login", requiresManual: true)
            }
            return .init(name: key, status: .degraded, detail: "\(name) smoke probe failed: \(reason)")
        default:
            return .init(name: key, status: .notChecked, detail: "auth not determined")
        }
    }

    /// Honest temporary-unavailability copy for a probe `.rateLimited` observation.
    ///
    /// PF-S02: the confidence guard governs the **whole sentence**, not just the
    /// observation's own reset field. `vendorReset` used to be spliced in ahead
    /// of the guard, so a limit *we* inferred could be dressed in a real reset
    /// time read off the vendor's usage screen — two sources, one confident
    /// sentence. That is how a Kimi seat answering prompts in the same minute
    /// read "Rate limited — resets Aug 14, 2026 at 11:11 AM". The plausible date
    /// is what made the invented limit credible, so it is the part to withhold.
    public static func rateLimitedDetail(observation: CapacityObservation, vendorReset: Date? = nil, now: Date = Date()) -> String {
        guard ProbeFreshnessGate.isVendorStated(observation)
        else { return "Rate limited — reset time unknown" }
        guard let reset = vendorReset ?? observation.observedResetAt else {
            return "Rate limited — reset time unknown"
        }
        guard let displayTime = VendorContinuityPresentation.resetDisplayTime(reset, now: now)
        else { return "Rate limited" }
        return "Rate limited — resets \(displayTime)"
    }

    private static func headlessTrustCheck(_ driverId: String, trust: HeadlessTrustPolicy) -> DoctorResult.Check {
        .init(
            name: "source.\(driverId).headlessTrust",
            status: .ok,
            detail: trust.disclosure,
            requiresManual: true)
    }

    private static func journalIncrementalCheck(_ runsOK: Bool) -> DoctorResult.Check {
        guard runsOK else {
            return .init(name: "journal.incrementalDurable", status: .critical,
                         detail: "run journal dir missing or not writable", requiresManual: true)
        }
        return .init(name: "journal.incrementalDurable", status: .ok,
                     detail: "run journal persists transitions incrementally")
    }

    private static func journalOrphanCheck(_ runsOK: Bool) -> DoctorResult.Check {
        guard runsOK else {
            return .init(name: "journal.orphanRecovery", status: .critical,
                         detail: "run journal dir missing or not writable", requiresManual: true)
        }
        return .init(name: "journal.orphanRecovery", status: .ok,
                     detail: "orphaned non-terminal runs resolve to interrupted")
    }

    private static func pendingReadableCheck(_ pendingOK: Bool) -> DoctorResult.Check {
        guard pendingOK else {
            return .init(name: "pending.storeReadable", status: .critical,
                         detail: "pending store dir missing or not readable", requiresManual: true)
        }
        return .init(name: "pending.storeReadable", status: .ok, detail: "pending store readable")
    }

    private static func pendingWritableCheck(_ pendingOK: Bool) -> DoctorResult.Check {
        guard pendingOK else {
            return .init(name: "pending.storeWritable", status: .critical,
                         detail: "pending store dir missing or not writable", requiresManual: true)
        }
        return .init(name: "pending.storeWritable", status: .ok, detail: "pending store writable")
    }

    private static func coordinatorCheck(_ coordinator: DoctorResult.Coordinator) -> DoctorResult.Check {
        switch coordinator.state {
        case .available:
            let pid = coordinator.pid.map { " (pid \($0))" } ?? ""
            return .init(name: "coordinator", status: .ok, detail: "background scheduler running\(pid)")
        case .foregroundOnly:
            return .init(name: "coordinator", status: .ok, detail: coordinator.detail)
        case .unavailable:
            return .init(name: "coordinator", status: .degraded, detail: coordinator.detail,
                         fixCommand: "alln serve", requiresManual: false)
        }
    }

    /// SC-S00 — the resident LaunchAgent is never painted healthy when launchd
    /// reports it wedged. `fixCommand` is `alln serve` for now; lifecycle
    /// register/repair is SC-S01.
    private static func serveLaunchAgentCheck(_ launchAgent: CoordinatorHealth.LaunchAgent?) -> DoctorResult.Check {
        guard let launchAgent else {
            return .init(name: "serve.launchAgent", status: .ok,
                         detail: "no resident LaunchAgent installed; foreground CLI only")
        }
        switch launchAgent.state {
        case .running:
            return .init(name: "serve.launchAgent", status: .ok, detail: launchAgent.detail)
        case .unknown:
            return .init(name: "serve.launchAgent", status: .notChecked, detail: launchAgent.detail)
        case .wedged:
            return .init(name: "serve.launchAgent", status: .critical, detail: launchAgent.detail,
                         fixCommand: "alln serve", requiresManual: false)
        }
    }

    private static func pilotCheck(_ pilot: PilotContext, inputs: Inputs) -> DoctorResult.Check {
        let seat = pilot.devWorkerLabel ?? pilot.devModelId ?? "(none remembered)"
        let project = pilot.projectLabel ?? "(project not found)"
        if !inputs.configDirWritable || !inputs.runsDirWritable || !inputs.pendingDirWritable {
            return .init(
                name: "pilot",
                status: .critical,
                detail: "pilot cannot start with \(seat) on \(project) — config or journal dirs are not writable",
                fixCommand: "alln doctor --json",
                requiresManual: true
            )
        }
        if pilot.projectLabel == nil {
            return .init(
                name: "pilot",
                status: .critical,
                detail: "pilot cannot start — project not found (pass `--project <id|path>`)",
                fixCommand: "alln project list --json",
                requiresManual: true
            )
        }
        if pilot.devModelId == nil {
            return .init(
                name: "pilot",
                status: .degraded,
                detail: "pilot cannot start on \(project) — no remembered dev seat (pass `--dev-model` on first `pilot start`)",
                fixCommand: "alln pair pilot start --doc <spec> --project \(projectToken(from: pilot)) --dev-model <seat>",
                requiresManual: true
            )
        }
        if !pilot.driverInstalled {
            return .init(
                name: "pilot",
                status: .critical,
                detail: "pilot cannot start with \(seat) on \(project) — dev driver not installed",
                fixCommand: "alln doctor --full",
                requiresManual: true
            )
        }
        if let ready = pilot.driverReady, !ready {
            return .init(
                name: "pilot",
                status: .degraded,
                detail: "pilot cannot start with \(seat) on \(project) — dev seat driver not ready (auth/smoke failed)",
                fixCommand: "alln doctor --full",
                requiresManual: true
            )
        }
        if pilot.driverReady == nil {
            return .init(
                name: "pilot",
                status: .ok,
                detail: "pilot can start with \(seat) on \(project) — driver installed; auth/readiness not checked on quota-free path",
                fixCommand: Self.fullFix
            )
        }
        return .init(
            name: "pilot",
            status: .ok,
            detail: "pilot can start with \(seat) on \(project) — dev seat ready"
        )
    }

    private static func projectToken(from pilot: PilotContext) -> String {
        pilot.projectLabel?.components(separatedBy: " (").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: ")")) ?? "."
    }

    private static func planWriterCheck(models: [Model], recByDriver: [String: ToolProbeRecord], full: Bool) -> DoctorResult.Check {
        // Strongest plan-writer (Claude Opus 5 over Antigravity Opus 4.6 fallback).
        guard let writer = TeamAssembler.strongestPlanWriter(in: models)
                ?? models.first(where: { $0.role == .planWriter || $0.role == .both }) else {
            return .init(name: "planWriterReady", status: .degraded, detail: "no plan-writer model configured", requiresManual: true)
        }
        guard full else {
            return .init(name: "planWriterReady", status: .notChecked, detail: "plan writer \(writer.displayName) configured; readiness not checked", fixCommand: fullFix)
        }
        let ready = recByDriver[writer.driverId]?.status.isSmokeReady ?? false
        return .init(name: "planWriterReady",
                     status: ready ? .ok : .degraded,
                     detail: ready ? "plan writer \(writer.displayName) ready" : "plan writer \(writer.displayName) not ready")
    }

    // MARK: - Overall status

    private static func overallStatus(
        records: [ToolProbeRecord],
        sourcesLoaded: Bool,
        inputs: Inputs,
        shellAllowlistRestrictive: Bool = false,
        binaryOffPath: Bool = false
    ) -> DoctorResult.Status {
        let nothingInstalled = !records.isEmpty && records.allSatisfy {
            if case .notInstalled = $0.status { return true } else { return false }
        }
        if !inputs.configDirWritable || !inputs.runsDirWritable || !inputs.pendingDirWritable || !sourcesLoaded || nothingInstalled {
            return .critical
        }
        if inputs.full && records.allSatisfy({ !$0.status.isSmokeReady }) && !records.isEmpty {
            return .critical   // probed and nothing is ready
        }
        // SC-S00: a wedged resident LaunchAgent can never read as "all fine".
        if inputs.coordinator?.launchAgent?.state == .wedged {
            return .degraded
        }
        let problem = !inputs.docsVersionMatchesBinary || shellAllowlistRestrictive || binaryOffPath || records.contains {
            switch $0.status {
            case .notInstalled, .shimmedNeedsConfirm, .probeFailed, .installedNotSignedIn, .rateLimited:
                return true
            default: return false
            }
        }
        return problem ? .degraded : .ok
    }
}
