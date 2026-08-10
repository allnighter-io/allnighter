import Foundation
import AllnighterCore
import AllnighterEngine
#if canImport(Darwin)
import Darwin
#endif

/// `alln` — Team-as-Tool (RB6). The universal shell surface any terminal
/// agent can call. Judgment only: links the team engine, never
/// worker-runner code. Local Fusion at zero marginal cost.
@main
struct AllnighterCLI {
    static func main() async {
        do {
            try SupportStartupMigrator.runOnce()
        } catch {
            fail(code: "SUPPORT_MIGRATION_FAILED", message: error.localizedDescription)
        }

        var args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--version" {
            runVersion([])
            return
        }
        let command = args.first ?? "help"
        if !args.isEmpty { args.removeFirst() }

        // Global `--help` funnel — every subcommand prints usage and exits 0.
        if CLIUsage.helpRequested(args), let text = CLIUsage.helpText(rootCommand: command, args: args) {
            print(text)
            return
        }

        // Fail closed on unknown flags and registry constraints before any handler
        // spends quota or starts a provider.
        if let cmdName = CLIUsage.resolveCommandName(rootCommand: command, args: args) {
            if let bad = CLIUsage.validateFlags(args: args, commandName: cmdName) {
                fail(code: "UNKNOWN_FLAG", message: bad.message)
            }
            if let bad = CLIUsage.validateFlagConstraints(args: args, commandName: cmdName) {
                fail(code: "CLI_USAGE_ERROR", message: bad.message)
            }
        }

        switch command {
        case "doctor" where args.first == "explain": runDoctorExplain(Array(args.dropFirst()))
        case "doctor" where args.first == "handoff": await runDoctorHandoff(Array(args.dropFirst()))
        case "doctor" where args.first == "silence": runDoctorSilence(Array(args.dropFirst()))
        case "serve": await runServe(args)
        default:
            let runtime = ToolRuntime()
            await run(command: command, args: args, runtime: runtime)
        }
    }

    private static func run(command: String, args: [String], runtime: ToolRuntime) async {
        switch command {
        case "teams" where args.first == "show": runTeamsShow(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "definition": runTeamsDefinition(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "duplicate": runTeamsDuplicate(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "new": runTeamsNew(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "edit": runTeamsEdit(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "set-default": runTeamsSetDefault(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "delete": runTeamsDelete(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "restore": runTeamsRestore(Array(args.dropFirst()), runtime)
        case "teams": runTeamCatalog(args, runtime)
        case "skills" where args.first == "show": runSkillShow(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "duplicate": runSkillsDuplicate(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "new": runSkillsNew(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "edit": runSkillsEdit(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "restore": runSkillsRestore(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "delete": runSkillsDelete(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "gc": runSkillsGC(Array(args.dropFirst()), runtime)
        case "skills": runSkillCatalog(args, runtime)
        case "thread" where args.first == "send": await ThreadSendCLI.runSend(Array(args.dropFirst()), runtime: runtime)
        case "thread" where args.first == "get": ThreadCLI.runGet(Array(args.dropFirst()))
        case "thread" where args.first == "status": ThreadCLI.runStatus(Array(args.dropFirst()))
        case "thread" where args.first == "attachment": ThreadCLI.runAttachmentGet(Array(args.dropFirst()))
        case "thread" where args.first == "rename": await ThreadRenameCLI.runRename(Array(args.dropFirst()), runtime: runtime)
        case "run": await RunCLI.run(args, runtime: runtime)
        case "continuity": runContinuity(args)
        // ORS-S03b: team status / team result hard-deleted — usage error only, never execute/forward.
        case "team" where args.first == "status":
            fail(
                code: "CLI_USAGE_ERROR",
                message: "team status is retired — use `alln show <run-id> --json` (or `--stream`) instead."
            )
        case "team" where args.first == "result":
            fail(
                code: "CLI_USAGE_ERROR",
                message: "team result is retired — use `alln show <run-id> --json` instead."
            )
        case "team" where args.first == "cancel": await runTeamCancel(Array(args.dropFirst()), runtime)
        case "team" where args.first == "reconcile": await runTeamReconcile(Array(args.dropFirst()), runtime)
        case "doctor": await runDoctor(args, runtime)
        case "detect": await runDetect(runtime)
        case "capacity": runCapacity(args)
        case "opencode-go": OpenCodeGoCLI.run(args)
        case "bailian-token-plan": BailianTokenPlanCLI.run(args)
        case "models": await ModelsCLI.run(args, runtime: runtime)
        case "drivers": await DriversCLI.run(args, runtime: runtime)
        case "catalog" where args.first == "validate": CatalogValidateCLI.run(Array(args.dropFirst()))
        case "defaults": await DefaultsCLI.run(args, runtime: runtime)
        case "boost-window": await BoostWindowCLI.run(args, runtime: runtime)
        case "help": await HelpCLI.run(args, runtime: runtime)
        case "history": await runHistory(args, runtime)
        case "docs": runDocs(args)
        case "menu" where args.first == "show": MenuCLI.runShow(Array(args.dropFirst()), runtime: runtime)
        case "menu": MenuCLI.run(args, runtime: runtime)
        case "show": runShow(args, runtime)
        case "floor" where args.first == "show": runFloorShow(Array(args.dropFirst()), runtime)
        case "artifact" where args.first == "show": ArtifactCLI.runShow(Array(args.dropFirst()), runtime: runtime)
        case "artifact" where args.first == "export": ArtifactCLI.runExport(Array(args.dropFirst()), runtime: runtime)
        case "spec": runSpec(args, runtime)
        case "export": runExport(args, runtime)
        case "dev": runDev(args)
        case "pair": await PairCLI.run(args, runtime: runtime)
        case "loop": await LoopCLI.run(args, runtime: runtime)
        case "pending": await PendingCLI.run(args.first, Array(args.dropFirst()), runtime: runtime)
        case "stalled": StalledCLI.run(args.first, Array(args.dropFirst()))
        case "project": await ProjectCLI.run(args.first, Array(args.dropFirst()), runtime: runtime)
        case "bootstrap": runBootstrap(args)
        case "install-cli": runInstallCLI(args)
        case "version": runVersion(args)
        case "update": runUpdate(args)
        case "ps": await runOwnershipPs(args)
        case "kill": await runOwnershipKill(args)
        case "gc": runOwnershipGC(args)
        case "--help", "-h": printHelp()   // "help" is handled above via HelpCLI
        default:
            FileHandle.standardError.write(Data("unknown command: \(command)\n".utf8)); printHelp(); exit(2)
        }
    }

    // MARK: - Subcommands

    /// Replay grammar for legacy show/export paths — always `alln run` (MR-S02).
    /// ADP-S01 — round-trips every explicit selector: the prompt, `--team`, each
    /// explicit `--model`, `--effort`, `--lane` (only when it was explicit context
    /// alongside a pinned worker, so an answer-team replay isn't given a redundant
    /// lane that could conflict with `--team`), and `--no-commit` when ordered.
    static func reproduceCommand(_ run: TeamRun) -> String {
        TeamRunReplayCommand.build(from: run)
    }

    /// Loads a persisted run for projection to `TeamRunJSON`, applying orphan
    /// recovery (a crashed non-terminal run reads back as `interrupted`).
    static func loadRun(_ runId: String) -> TeamRun? {
        RunStore().load(runId: runId)
    }

    /// Emits the shared machine failure envelope (one JSON object on stdout). The
    /// recovery fields (`ruleId`/`agentAction`/`requiresManual`/`retryable`) are
    /// taken from the error catalog so the emitted envelope and `error_explain`
    /// always agree (M-C).
    static func emitFailure(
        code: String,
        message: String,
        supportDir: String? = nil,
        suggestions: [String] = [],
        candidates: [ExactIdResolver.Candidate] = [],
        nextAction: AgentNextAction? = nil
    ) {
        struct Failure: Encodable { let schemaVersion = 1; let success = false; let error: ErrorEnvelope }
        let spec = ContractRegistry.milestone1.errorSpec(for: code)
        let enriched = ErrorDiscovery.messageWithSuggestions(message, suggestions: suggestions)
        let env = ErrorEnvelope(
            code: code,
            ruleId: spec?.ruleId,
            message: enriched,
            agentAction: spec?.agentAction,
            requiresManual: spec?.requiresManual ?? false,
            retryable: spec?.retryable ?? false,
            supportDir: supportDir,
            suggestions: suggestions,
            candidates: candidates,
            nextAction: nextAction ?? ErrorDiscovery.nextAction(forErrorCode: code)
        )
        print(jsonString(Failure(error: env)))
    }

    /// Emits the failure envelope and exits with the catalog-derived process exit
    /// code (usage → 2, operational → 1). The single funnel for terminal CLI
    /// failures so the error code and its exit class can never drift apart (M-C).
    static func fail(
        code: String,
        message: String,
        supportDir: String? = nil,
        suggestions: [String] = [],
        candidates: [ExactIdResolver.Candidate] = [],
        nextAction: AgentNextAction? = nil
    ) -> Never {
        emitFailure(
            code: code, message: message, supportDir: supportDir,
            suggestions: suggestions, candidates: candidates, nextAction: nextAction)
        exit(ContractRegistry.milestone1.processExitCode(forErrorCode: code))
    }

    /// MR-S04 — honor-or-fail every explicit `--model` / `--team` / `--seat` before dispatch.
    static func requireExactSelectors(
        workerId: String?,
        teamId: String?,
        seatModelIds: [String] = [],
        models: [Model],
        teams: [TeamPreset]
    ) {
        if let workerId, !workerId.isEmpty {
            if case .failure(let failure) = ExactIdResolver.resolveWorker(
                workerId, flag: "--model", models: models
            ) {
                failExactId(failure)
            }
        }
        for (index, seatId) in seatModelIds.enumerated() where !seatId.isEmpty {
            if case .failure(let failure) = ExactIdResolver.resolveWorker(
                seatId, flag: "--seat[\(index + 1)]", models: models
            ) {
                failExactId(failure)
            }
        }
        if let teamId, !teamId.isEmpty {
            let lookup = teams.isEmpty ? TeamCatalog.all : teams
            if case .failure(let failure) = ExactIdResolver.resolveTeam(
                teamId, flag: "--team", teams: lookup
            ) {
                failExactId(failure)
            }
        }
    }

    static func failExactId(_ failure: ExactIdResolver.Failure) -> Never {
        fail(
            code: failure.code,
            message: failure.message,
            suggestions: failure.suggestionIds,
            candidates: failure.candidates,
            nextAction: AgentNextAction(
                kind: "discover",
                label: "List menu rows",
                command: failure.discoveryCommand
            )
        )
    }

    /// Effective `ALLNIGHTER_SUPPORT_DIR` (RLR-L1) — surfaced in not-found / kill
    /// errors so a caller on the wrong or isolated config home can see the exact
    /// support root that was searched (RCA class 5).
    static func effectiveSupportDir() -> String { AllnighterPaths.support.path }

    /// S01c (RLR-L8): distinguishes "no run.json for this id at all"
    /// (`RUN_NOT_FOUND` territory) from "a run.json exists but failed to
    /// decode" (`JOURNAL_CORRUPT`) — checked before every not-found fallback
    /// so an unmappable/legacy journal is never silently reported as if the
    /// run never existed, and never has a status invented for it. `store`
    /// defaults to the production `RunStore()`; status/result/cancel sites
    /// pass the same `RunStore` the async team service already resolved so
    /// isolated test stores are respected too.
    static func journalCorruptDetail(_ runId: String, in store: RunStore = RunStore()) -> String? {
        guard case .failure(.corrupt(_, let detail)) = store.loadRawResult(runId: runId) else { return nil }
        return detail
    }

    /// A `RUN_NOT_FOUND` failure that names the effective support root in both the
    /// human message and the machine `supportDir` field (RLR-L1), then exits.
    /// Upgrades to `JOURNAL_CORRUPT` when `runId` names an existing-but-corrupt
    /// journal (S01c) — pass `nil` when there is no single candidate id (e.g. a
    /// `latest` reference that matched nothing).
    static func failRunNotFound(_ runId: String?, _ message: String, in store: RunStore = RunStore()) -> Never {
        let dir = effectiveSupportDir()
        if let runId, let detail = journalCorruptDetail(runId, in: store) {
            fail(
                code: "JOURNAL_CORRUPT",
                message: "run journal for \(runId) exists but could not be decoded: \(detail) (support dir: \(dir))",
                supportDir: dir
            )
        }
        fail(code: "RUN_NOT_FOUND", message: "\(message) (support dir: \(dir))", supportDir: dir)
    }

    /// Non-exiting variant for JSON emit paths that own their own `exit`. Same
    /// `JOURNAL_CORRUPT` upgrade as `failRunNotFound` (S01c).
    static func emitRunNotFound(_ runId: String?, _ message: String, in store: RunStore = RunStore()) {
        let dir = effectiveSupportDir()
        if let runId, let detail = journalCorruptDetail(runId, in: store) {
            emitFailure(
                code: "JOURNAL_CORRUPT",
                message: "run journal for \(runId) exists but could not be decoded: \(detail) (support dir: \(dir))",
                supportDir: dir
            )
            return
        }
        emitFailure(code: "RUN_NOT_FOUND", message: "\(message) (support dir: \(dir))", supportDir: dir)
    }

    static func emitCatalogError(_ error: CatalogError, skillContext: Bool = false) -> Never {
        let (code, message) = catalogErrorEnvelope(error, skillContext: skillContext)
        fail(code: code, message: message)
    }

    static func catalogErrorEnvelope(_ error: CatalogError, skillContext: Bool = false) -> (code: String, message: String) {
        switch error {
        case .teamNotFound: return ("TEAM_NOT_FOUND", "team not found")
        case .skillNotFound: return ("SKILL_NOT_FOUND", "skill not found")
        case .modelNotFound: return ("MODEL_NOT_FOUND", "model not found")
        case .builtInImmutable:
            return (skillContext ? "SKILL_BUILTIN_IMMUTABLE" : "TEAM_BUILTIN_IMMUTABLE", "built-in catalog entry cannot be changed")
        case .idCollision:
            return (skillContext ? "SKILL_ID_COLLISION" : "TEAM_ID_COLLISION", "catalog id already exists")
        case .idInvalid: return ("CATALOG_ID_INVALID", "catalog id is invalid")
        case .teamInvalid(let detail): return ("TEAM_INVALID", detail)
        case .skillInvalid(let detail): return ("SKILL_INVALID", detail)
        case .skillLaneMismatch(let skillId, let teamId):
            return ("SKILL_LANE_MISMATCH", "skill \(skillId) is not in the same lane as team \(teamId)")
        case .skillInUse(let ids):
            return ("SKILL_IN_USE", "skill is referenced by team(s): \(ids.joined(separator: ", "))")
        case .teamDefaultInvalid(let detail): return ("TEAM_DEFAULT_INVALID", detail)
        case .restoreUnsupported:
            return (skillContext ? "SKILL_RESTORE_UNSUPPORTED" : "TEAM_RESTORE_UNSUPPORTED",
                    skillContext ? "this skill has no shipped version to restore" : "this team has no shipped version to restore")
        }
    }

    static func modelCatalogErrorEnvelope(_ error: ModelCatalogError) -> (code: String, message: String) {
        switch error {
        case .notFound(let id): return ("MODEL_NOT_FOUND", "unknown model: \(id)")
        case .builtInImmutable: return ("MODEL_BUILTIN_IMMUTABLE", "built-in model cannot be changed")
        case .idCollision: return ("MODEL_ID_COLLISION", "model id already exists")
        case .idInvalid: return ("MODEL_INVALID", "model id is invalid")
        case .driverMissing(let driver): return ("MODEL_DRIVER_MISSING", "unknown driver: \(driver)")
        case .invalid(let detail): return ("MODEL_INVALID", detail)
        }
    }

    static func runHistory(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let query = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln history \"<query>\"\n".utf8)); exit(2)
        }
        let hits = await runtime.service().recall(query: query)
        if opts.flag("json") {
            print(jsonString(HistoryJSON(contractVersion: ContractRegistry.contractVersion, query: query, results: hits)))
        } else if hits.isEmpty {
            print("(no prior team runs match)")
        } else {
            for h in hits { print("\(h.createdAt) · \(h.runId)\n  \(h.prompt)\n  \(h.planExcerpt.replacingOccurrences(of: "\n", with: " ").prefix(160))\n") }
        }
    }

    /// `alln capacity [--json] [--refresh] [--source <id>] [--dogfood]` — vendor quota strip.
    ///
    /// **Bare** (default): while the Dock app is open, reads the resident's
    /// gated in-memory snapshot over `capacity.sock` (CWB-S02 — read-only,
    /// never starts probes). Socket miss / hang / bad version → one cold live
    /// acquire for all bench seats (measured budget). No disk, no history
    /// hydrate-as-live. Always prints the full seven-row table (TTY or piped).
    ///
    /// **`--refresh`**: legacy no-op; bare is already live. Kept for scripts.
    ///
    /// **`--source <id>`**: live probe of one seat (explicit per-seat
    /// diagnostics — bypasses the socket), still returning all seven rows;
    /// unprobed siblings show `neverSampled`.
    ///
    /// **`--dogfood --source opencode_go`**: developer-only direct dashboard
    /// scrape (shows only the opencode_go row, not the full bench). Omit
    /// `--dogfood` for normal use — opencode_go is a regular bench member.
    ///
    /// **`--shadow-pane-reader`**: developer-only diagnostic (not a product
    /// surface). Forces a live probe and runs the model reader alongside the
    /// deterministic parser for whichever seats reach that branch this call —
    /// today that is only `cursor_agent` / `kimi`, the two without a native
    /// channel — logging any disagreement to
    /// `~/Library/Application Support/Allnighter/Capacity/shadow/disagreements.jsonl`.
    /// Never published as a capacity value (Handover_Capacity_2026-08-08.md
    /// §5); never reachable from `alln serve`'s background refresh.
    ///
    /// Unknown / disabled / expired are loud, never blocks (exit 0). Non-TTY
    /// path is plain ASCII, zero ANSI.
    static func runCapacity(_ args: [String]) {
        let opts = Options(args)
        // Setting operations run before anything else and never read a meter:
        // turning capacity OFF must not be the thing that probes it.
        if opts.flag("enable") || opts.flag("disable") {
            runCapacityFeatureToggle(enable: opts.flag("enable"), disable: opts.flag("disable"))
            return
        }
        let now = Date()
        let refreshFlag = opts.flag("refresh")
        let dogfood = opts.flag("dogfood")
        // Diagnostic-only opt-in (Handover_Capacity_2026-08-08.md §5): runs
        // the model reader alongside the deterministic parser for whichever
        // sources reach that branch this invocation (in practice cursor_agent
        // / kimi — the two without a native channel, Capacity_Native_Channels
        // §v5) and logs disagreements. Never wired into `alln serve`'s
        // scheduler or the Mac resident's periodic refresh — see
        // `CapacityProbe.maybeRunShadow`. Forces a live probe (below), since
        // there is no capture text to shadow-compare against a cached socket
        // answer.
        let shadowPaneReader = opts.flag("shadow-pane-reader")
        let refreshSource = opts.value("source")
        if let refreshSource, let message = CapacityAcquisition.validateRefreshSourceId(refreshSource, dogfood: dogfood) {
            fail(code: "CLI_USAGE_ERROR", message: message)
        }
        if dogfood {
            guard let refreshSource else {
                fail(
                    code: "CLI_USAGE_ERROR",
                    message: "--dogfood requires --source <dashboard_id>"
                )
            }
            capacityProgress("capacity: dogfood \(refreshSource) scrape…")
            let featureEnabled = CapacityFeatureSettingsPersistence().loadEnabled()
            switch refreshSource {
            case CapacityAcquisition.dogfoodSourceId:
                let dogfoodBench = CapacityFetch.dogfoodOpenCodeGoSnapshot(now: now, featureEnabled: featureEnabled)
                let bench = dogfoodBench.snapshot
                let diagnostics = dogfoodBench.diagnostics
                capacityProgress(
                    "\(refreshSource): \(diagnostics.ok ? "ok" : "failed")"
                        + " strategy=\(diagnostics.parserStrategy ?? "-")"
                        + " http=\(diagnostics.httpStatus.map(String.init) ?? "-")"
                        + " kind=\(diagnostics.failureKind ?? "none")"
                )
                emitCapacityOutput(rows: bench.rows, now: now, json: opts.flag("json"))
            case CapacityAcquisition.bailianTokenPlanSourceId:
                let dogfoodBench = CapacityFetch.dogfoodBailianTokenPlanSnapshot(now: now, featureEnabled: featureEnabled)
                let bench = dogfoodBench.snapshot
                let diagnostics = dogfoodBench.diagnostics
                capacityProgress(
                    "\(refreshSource): \(diagnostics.ok ? "ok" : "failed")"
                        + " strategy=\(diagnostics.parserStrategy ?? "-")"
                        + " http=\(diagnostics.httpStatus.map(String.init) ?? "-")"
                        + " kind=\(diagnostics.failureKind ?? "none")"
                )
                emitCapacityOutput(rows: bench.rows, now: now, json: opts.flag("json"))
            default:
                fail(
                    code: "CLI_USAGE_ERROR",
                    message: "--dogfood requires --source \(CapacityAcquisition.dogfoodSourceId) or \(CapacityAcquisition.bailianTokenPlanSourceId)"
                )
            }
            return
        }

        // Feature OFF: zero probes from every trigger (CWB-S01b).
        let featureEnabled = CapacityFeatureSettingsPersistence().loadEnabled()

        // CWB-S02 fast path: one read of the resident snapshot over
        // capacity.sock. Any failure (app quit, stale socket, hang, foreign
        // schema version) → nil → one cold live acquire — never a retry.
        let socketAnswer: CapacitySocketSnapshot? = (featureEnabled && refreshSource == nil && !shadowPaneReader)
            ? CapacitySocketClient.read()
            : nil

        if featureEnabled {
            let target = refreshSource.map { " \($0)" } ?? ""
            if let answer = socketAnswer {
                capacityProgress("capacity: resident snapshot (\(socketAgeLabel(answer, now: now)))")
            } else if refreshFlag {
                capacityProgress("capacity: refreshing\(target)…")
            } else {
                capacityProgress("capacity: live acquire\(target)…")
            }
        }

        let bench: CapacityFetch.Snapshot = {
            guard featureEnabled else {
                return CapacityFetch.disabledSnapshot(now: now)
            }
            if let answer = socketAnswer {
                return CapacitySocketFastPath.snapshot(from: answer, now: now)
            }
            return CapacityFetch.liveSnapshot(
                now: now,
                refreshSource: refreshSource,
                shadowPaneReader: shadowPaneReader
            )
        }()

        if featureEnabled, socketAnswer == nil {
            capacityProgress("capacity: done")
        }
        emitCapacityOutput(rows: bench.rows, now: now, json: opts.flag("json"))
    }

    /// `alln capacity --enable | --disable` — the only supported way to flip the
    /// capacity feature.
    ///
    /// `CapacityFeatureSettingsPersistence.saveEnabled` existed with no caller,
    /// so the only way to turn capacity off was hand-editing JSON. That blocked
    /// the Capacity Warm Bench trust-gate row "Feature OFF: zero timer probes",
    /// which cannot be exercised if the feature cannot be turned off.
    ///
    /// Default stays ON: a missing config file means enabled, and nothing here
    /// writes a file until the owner asks for one.
    static func runCapacityFeatureToggle(enable: Bool, disable: Bool) {
        guard enable != disable else {
            fail(
                code: "CLI_USAGE_ERROR",
                message: "--enable and --disable are mutually exclusive",
                suggestions: ["alln capacity --enable", "alln capacity --disable"]
            )
        }
        let store = CapacityFeatureSettingsPersistence()
        do {
            try store.saveEnabled(enable)
        } catch {
            fail(
                code: "INTERNAL_ERROR",
                message: "failed to persist capacity setting: \(error.localizedDescription)"
            )
        }
        // Read back rather than echo the request: report what is true, not what
        // was asked for. A failed write must never print success.
        let persisted = store.loadEnabled()
        guard persisted == enable else {
            fail(
                code: "INTERNAL_ERROR",
                message: "capacity setting did not persist — still \(persisted ? "enabled" : "disabled")"
            )
        }
        print("Capacity feature: \(enable ? "enabled" : "disabled")")
        if enable {
            print("Next: alln capacity")
        } else {
            print("No seats will be probed. Re-enable with: alln capacity --enable")
        }
    }

    private static func emitCapacityOutput(rows: [CapacityBenchRow], now: Date, json: Bool) {
        if json {
            let payload = CapacityStripRenderer.json(
                rows: rows,
                now: now,
                contractVersion: ContractRegistry.contractVersion
            )
            print(jsonString(payload))
            return
        }
        if capacityStdoutIsTTY() {
            print(CapacityStripRenderer.renderTTY(rows: rows, now: now))
        } else {
            print(CapacityStripRenderer.renderPlain(rows: rows, now: now))
        }
    }

    /// Progress / diagnostics for capacity refresh — stderr only so stdout stays
    /// a clean table or JSON contract for agents.
    private static func capacityProgress(_ line: String) {
        let message = line + "\n"
        if let data = message.data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }

    /// One-line age honesty for a socket-served answer (CWB-S02). Instant
    /// delivery never hides how old the snapshot is.
    private static func socketAgeLabel(_ answer: CapacitySocketSnapshot, now: Date) -> String {
        if answer.disabled { return "feature OFF" }
        guard let settledAt = answer.settledAt else { return "warming — no settle yet" }
        let minutes = max(0, Int(now.timeIntervalSince(settledAt) / 60))
        return minutes < 1 ? "age <1m" : "age \(minutes)m"
    }

    /// CWB-S00b — menu capacity stays omitted until the Resident trust gate.
    /// Returns `nil` so `alln menu` / `alln menu show` / `alln bootstrap --json`
    /// never inject a strip and never spawn a probe.
    static func menuCapacity(
        now: Date,
        probeExecutor: (any CapacityProbeExecuting)? = nil
    ) -> MenuJSON.Capacity? {
        _ = now
        _ = probeExecutor
        return nil
    }

    /// OPC-S06 — release-channel announcement for menu / version / doctor.
    /// Fail-open: never throws, never blocks seating. Uses the shared
    /// `ReleaseChannel` cache (24h TTL, 2s timeout). Not called from `run`.
    static func menuUpdate(now: Date = Date()) -> ReleaseUpdateInfo? {
        ReleaseChannel.checkUpdate(
            currentVersion: binaryVersion,
            binaryPath: ProcessOwnership.currentExecutablePath()
                ?? CommandLine.arguments.first,
            now: now
        )
    }

    /// Local TTY probe for the capacity strip (mirrors PilotCLI — not shared).
    private static func capacityStdoutIsTTY() -> Bool {
        #if canImport(Darwin)
        return isatty(STDOUT_FILENO) == 1
        #else
        return false
        #endif
    }

    /// ADP-S05: single-sourced from `AllnighterVersionIdentity` (AllnighterCore) —
    /// do not hardcode a semver literal here.
    static let binaryVersion = AllnighterVersionIdentity.binaryVersion

    /// `alln doctor [--json] [--full]` — the product recovery surface. Default is
    /// quota-free (resolve + version + local checks; auth/smoke/readiness reported
    /// `notChecked`). `--full` runs smoke probes (spends quota) to confirm
    /// auth/readiness. Emits `DoctorResult` (docs/archive/phases/CLI_Implementation_Contract.md
    /// §Doctor Contract).
    static func runDoctor(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        let full = opts.flag("full")
        let pilot = opts.flag("pilot")
        let sourceId = opts.value("agent")
        if let sourceId, runtime.registry.manifest(id: sourceId) == nil {
            fail(code: "SOURCE_NOT_FOUND", message: "no source manifest '\(sourceId)'")
        }
        let result = await SourceProbeService(
            models: runtime.models,
            registry: runtime.registry,
            binaryVersion: binaryVersion
        ).probe(.init(
            sourceId: sourceId,
            full: full,
            pilot: pilot,
            projectToken: opts.value("project"),
            workspaceHeadSha: workspaceHeadGitSha()
        ))
        if opts.flag("json") {
            print(jsonString(result))   // exactly one JSON object, no prose
        } else {
            printDoctorHuman(result, full: full)
        }
    }

    /// `alln serve [--health --json]` / `alln serve repair|enable|disable
    /// [--json]` — the optional background scheduler (Pending wake, Boost
    /// seeding, vendor-backoff continuation, cloud relay). It owns no run
    /// semantics: `alln run` never needs it. `--health` is read-only and
    /// never starts it.
    static func runServe(_ args: [String]) async {
        let opts = Options(args)
        if opts.positional.first == "repair" {
            runServeRepair(opts)
            return
        }
        if opts.positional.first == "enable" {
            runServeEnable(opts)
            return
        }
        if opts.positional.first == "disable" {
            runServeDisable(opts)
            return
        }
        if opts.flag("health") {
            let health = ServeDaemonProbe().health(binaryVersion: binaryVersion)
            if opts.flag("json") {
                print(jsonString(health))
            } else {
                print("serve \(health.state.rawValue)")
                if let pid = health.pid { print("pid \(pid)") }
                if let port = health.loopback.port { print("loopback \(health.loopback.host):\(port)") }
                print("obligations \(health.activeObligationCount)")
            }
            return
        }
        if !opts.positional.isEmpty || !opts.values.isEmpty {
            FileHandle.standardError.write(Data("usage: alln serve [--health --json] | alln serve repair|enable|disable [--json]\n".utf8)); exit(2)
        }
        // Singleton + takeover. Four daemons were found running on the dogfood
        // host (oldest nine days), each executing a different build — so every
        // serve-hosted fix silently failed to take effect after a rebuild.
        // A newer build supersedes an older one: stale code must not win by
        // seniority.
        let daemonStore = ServeDaemonStore()
        switch ServeDaemonAdmission.decide(
            existing: daemonStore.load(), isAlive: ServeDaemonAdmission.processIsAlive
        ) {
        case .refuse(let pid, let version):
            FileHandle.standardError.write(Data(
                ("alln serve: already running (pid \(pid), \(version), same build) — nothing to do.\n"
                 + "Stop it with `kill \(pid)` if you want a fresh one.\n").utf8))
            exit(0)
        case .supersede(let pid, let version, let sha):
            FileHandle.standardError.write(Data(
                "alln serve: superseding older daemon (pid \(pid), \(version), \(sha.prefix(12)))\n".utf8))
            guard ServeDaemonAdmission.stop(pid: pid) else {
                FileHandle.standardError.write(Data(
                    "alln serve: pid \(pid) survived TERM and KILL — refusing to start a second daemon.\n".utf8))
                exit(1)
            }
            daemonStore.clear()
        case .start:
            daemonStore.clear()
        }
        // The record is not the only truth. Three daemons were found running
        // with NO record at all: one shared record file means the last process
        // to exit clears it for everyone, and daemons started before this
        // admission existed never wrote one. Sweep the process table too.
        for pid in ServeDaemonAdmission.runningServePIDs() {
            FileHandle.standardError.write(Data(
                "alln serve: stopping unrecorded daemon (pid \(pid))\n".utf8))
            guard ServeDaemonAdmission.stop(pid: pid) else {
                FileHandle.standardError.write(Data(
                    "alln serve: pid \(pid) survived TERM and KILL — refusing to start a second daemon.\n".utf8))
                exit(1)
            }
        }
        FileHandle.standardError.write(Data("alln serve — background scheduler (Ctrl+C to stop)\n".utf8))
        do {
            let runtime = ToolRuntime()
            let wake = ServeDaemon.WakeDependencies(
                models: runtime.models,
                registry: runtime.registry,
                teams: runtime.teams,
                invocations: runtime.invocations,
                asyncTeam: runtime.asyncTeamService(),
                readyModels: { runtime.readyModels }
            )
            var remoteDependencies: ServeDaemon.RemoteDependencies?
            if let environment = RemoteSupabaseEnvironment.load(), environment.hasMacAgentCredentials {
                do {
                    let runStore = RunStore()
                    let threadStore = ThreadStore()
                    let journal = RemoteRunEventJournal(rootDirectory: runStore.rootDirectory)
                    let asyncTeam = AsyncTeamService(
                        models: runtime.models,
                        registry: runtime.registry,
                        teams: runtime.teams,
                        config: runtime.config,
                        runStore: runStore,
                        governor: runtime.governor,
                        remoteEventJournal: journal,
                        invocations: runtime.invocations
                    )
                    let baseExecutor = AsyncTeamRemoteCommandExecutor(
                        service: asyncTeam,
                        readyModels: { runtime.models }
                    )
                    let executor = RemoteIOSThreadMirrorExecutor(
                        underlying: baseExecutor,
                        threadStore: threadStore,
                        runStore: runStore
                    )
                    let inputs = RemoteMacAgentServeAssembly.Inputs(
                        environment: environment,
                        executor: executor,
                        readyModels: { runtime.models },
                        runStore: runStore,
                        threadStore: threadStore,
                        journal: journal
                    )
                    remoteDependencies = try RemoteMacAgentServeAssembly.remoteDependencies(inputs: inputs)
                    FileHandle.standardError.write(Data("remote agent: cloud relay enabled\n".utf8))
                } catch {
                    FileHandle.standardError.write(
                        Data("remote agent disabled: \(error)\n".utf8)
                    )
                }
            }
            try await ServeDaemon(
                binaryVersion: binaryVersion,
                wakeDependencies: wake,
                remoteDependencies: remoteDependencies
            ).runUntilSignal()
        } catch {
            FileHandle.standardError.write(Data("serve failed: \(error)\n".utf8)); exit(1)
        }
    }

    /// `alln serve repair [--json]` — SC-S01 removal of the unsupported
    /// CODE_RED LaunchAgent (`com.allnighter.resident-coordinator`). Observes
    /// with SC-S00's `ServeLaunchAgentStatus` (the wedge rule lives there);
    /// absent is a no-op success, anything else (wedged or an installed orphan
    /// plist) is removed via `ServeLifecycle.remove` (bootout + plist delete).
    /// Never starts serve and never registers a replacement agent (SC-S04).
    /// Exit 0 on removed/absent, non-zero on failed.
    private static func runServeRepair(_ opts: Options) {
        let report = ServeLifecycle().repair(observation: ServeLaunchAgentStatus().observe())
        let detail = report.removal?.detail
            ?? "no \(ServeLaunchAgentStatus.label) LaunchAgent installed — nothing to remove"
        if opts.flag("json") {
            print(jsonString(report))
        } else {
            let stream = report.outcome == .failed ? FileHandle.standardError : FileHandle.standardOutput
            stream.write(Data("serve repair \(report.outcome.rawValue): \(detail)\n".utf8))
            if report.outcome == .removed {
                print("serve not started — run `alln serve` in a terminal to start the background scheduler.")
            }
        }
        if report.outcome == .failed { exit(1) }
    }

    /// `alln serve enable [--json]` — SC-S04b product-owned LaunchAgent
    /// (opt-in start-at-login). Stages the stable binary when missing, boots
    /// out any leftover CODE_RED registration, writes the product plist aimed
    /// at the staged binary, and bootstraps it. Exit 0 on enabled, non-zero
    /// on failed.
    private static func runServeEnable(_ opts: Options) {
        let result = ServeLifecycle().enable()
        if opts.flag("json") {
            print(jsonString(result))
        } else {
            let stream = result.outcome == .failed ? FileHandle.standardError : FileHandle.standardOutput
            stream.write(Data("serve enable \(result.outcome.rawValue): \(result.detail)\n".utf8))
        }
        if result.outcome == .failed { exit(1) }
    }

    /// `alln serve disable [--json]` — SC-S04b unregisters the LaunchAgent:
    /// bootout + plist delete, leaving no orphan. Exit 0 on removed/absent,
    /// non-zero on failed.
    private static func runServeDisable(_ opts: Options) {
        let result = ServeLifecycle().disable()
        if opts.flag("json") {
            print(jsonString(result))
        } else {
            let stream = result.outcome == .failed ? FileHandle.standardError : FileHandle.standardOutput
            stream.write(Data("serve disable \(result.outcome.rawValue): \(result.detail)\n".utf8))
        }
        if result.outcome == .failed { exit(1) }
    }

    private static func printDoctorHuman(_ r: DoctorResult, full: Bool) {
        print("alln doctor — \(r.status.rawValue)\(full ? " (full)" : "")")
        if let counsel = r.counsel { print(counsel) }
        for c in r.checks {
            let mark: String
            switch c.status {
            case .ok: mark = "✓"
            case .degraded: mark = "!"
            case .critical: mark = "✗"
            case .notChecked: mark = "·"
            }
            print("  \(mark) \(c.name)\t\(c.detail)")
            if let fix = c.fixCommand { print("    → \(fix)") }
        }
        if !full {
            print("\nAuth/readiness not probed (quota-free). Run `alln doctor --full` to confirm — spends quota.")
        }
        for action in r.nextActions { print("→ \(action.command)") }
    }

    /// First-run CLI detection, headless — proves the detector on a real machine
    /// before any Setup UI (docs/phases/setup/01 §11, Phase 1). Runs real smoke
    /// probes. Note: the CLI uses `DefaultConfig` (no `setup` blocks yet), so bins
    /// fall back to `invoke.command` and loginFlow guidance comes from the app's
    /// bundle registry, not here.
    static func runDetect(_ runtime: ToolRuntime) async {
        let result = await SourceProbeService(
            models: runtime.models,
            registry: runtime.registry,
            binaryVersion: binaryVersion
        ).detect()

        for r in result.records.sorted(by: { $0.driverId < $1.driverId }) {
            let path = r.invocation?.resolvedPath ?? "—"
            switch r.status {
            case .ready(let v):
                print("\(r.driverId)\tREADY\t\(v)\t\(path)")
            case .installedNotProbed(let v):
                print("\(r.driverId)\tINSTALLED (not probed)\t\(v)\t\(path)")
            case .installedNotSignedIn(let f):
                print("\(r.driverId)\tNEEDS SIGN-IN\t\(r.version ?? "")\n  → \(f.instructions)")
            case .rateLimited(let observation):
                print("\(r.driverId)\tRATE LIMITED\t\(r.version ?? "")\n  → \(DoctorReport.rateLimitedDetail(observation: observation))")
            case .probeFailed(let reason):
                print("\(r.driverId)\tPROBE FAILED\t\(r.version ?? "")\n  → \(reason)")
            case .shimmedNeedsConfirm(let res):
                print("\(r.driverId)\tNEEDS PATH\t\(res.rawCommandV)")
            case .notInstalled:
                let detail: String
                if let manifest = runtime.registry.manifest(id: r.driverId) {
                    detail = SetupRecoveryCopy.notInstalledDetail(for: manifest)
                } else {
                    detail = "(no binary on PATH or known paths)"
                }
                print("\(r.driverId)\tNOT INSTALLED\t\(detail)")
                if let manifest = runtime.registry.manifest(id: r.driverId) {
                    if let install = SetupRecoveryCopy.notInstalledInstallShellCommand(for: manifest) {
                        print("  → \(install)")
                    }
                    if let docs = SetupRecoveryCopy.notInstalledFixCommand(for: manifest) {
                        print("  → \(docs)")
                    }
                }
            }
        }
        let tally = BenchTallyProjector.tally(
            registry: runtime.registry,
            records: result.records,
            parked: SetupStore().load().parkedSet
        )
        print(
            "\nBench: \(tally.headline.rawValue) — \(tally.ready) ready · \(tally.needsStep) need a step · \(tally.notInstalled) not installed · \(tally.needsCheck) need check (of \(tally.supported) supported)"
        )
        print("Assembled team: \(result.assembledTeam.benchModelIds.count) ready model(s); plan writer: \(result.assembledTeam.planWriterModelId ?? "—") · saved")
    }

    /// `alln dev export-contracts [--check]` — regenerate or verify the
    /// checked-in generated artifacts from the contract registry
    /// (docs/archive/phases/CLI_Implementation_Contract.md §Generated Artifacts). The
    /// generated dir is resolved relative to the current directory, so run this
    /// from the repo root.
    static func runDev(_ args: [String]) {
        var rest = args
        let sub = rest.first
        if !rest.isEmpty { rest.removeFirst() }
        switch sub {
        case "export-contracts": runExportContracts(Options(rest))
        default:
            FileHandle.standardError.write(Data("usage: alln dev export-contracts [--check]\n".utf8)); exit(2)
        }
    }

    static func runExportContracts(_ opts: Options) {
        let cwd = FileManager.default.currentDirectoryPath
        if opts.flag("check") {
            do {
                switch try ContractExport.check(from: cwd) {
                case .upToDate(let count):
                    print("contracts up to date (\(count) artifacts)")
                case .drifted(let files):
                    FileHandle.standardError.write(Data("CONTRACT_DRIFT: \(files.joined(separator: ", "))\nRun `alln dev export-contracts`, then rebuild.\n".utf8))
                    exit(ContractRegistry.milestone1.processExitCode(forErrorCode: "CONTRACT_DRIFT"))
                case .versionNotBumped(let lockedVersion, _, let currentHash):
                    fail(
                        code: "CONTRACT_VERSION_NOT_BUMPED",
                        message: "contract surface hash changed (\(currentHash.prefix(12))…) but contractVersion is still \(lockedVersion). Bump ContractRegistry.contractVersion, then run `alln dev export-contracts`."
                    )
                }
            } catch let notFound as ContractExport.NotFoundError {
                failContractsNotFound(notFound)
            } catch {
                FileHandle.standardError.write(Data("export failed: \(error)\n".utf8)); exit(1)
            }
        } else {
            do {
                let result = try ContractExport.write(from: cwd)
                print("wrote \(result.count) artifacts to \(result.path)")
            } catch let notFound as ContractExport.NotFoundError {
                failContractsNotFound(notFound)
            } catch {
                FileHandle.standardError.write(Data("write failed: \(error)\n".utf8)); exit(1)
            }
        }
    }

    /// Emits `CONTRACT_ARTIFACTS_NOT_FOUND` — distinct from `CONTRACT_DRIFT` — for
    /// an unresolved repo root or a missing generated dir/artifact (PO-F6).
    static func failContractsNotFound(_ error: ContractExport.NotFoundError) -> Never {
        let message: String
        switch error {
        case .repoRootNotFound(let cwd):
            message = "could not find the repo root ascending from \(cwd) (looked for docs/generated/alln or .git); re-run from inside the repo."
        case .generatedDirMissing(let path):
            message = "\(path) does not exist yet; this is not content drift — run `alln dev export-contracts` to create it."
        case .artifactsMissing(let path, let filenames):
            message = "missing artifact file(s) under \(path): \(filenames.joined(separator: ", ")); this is not content drift — run `alln dev export-contracts` to (re)create them."
        }
        fail(code: "CONTRACT_ARTIFACTS_NOT_FOUND", message: message)
    }

    // MARK: - teams catalog / docs / show / export / doctor explain

    /// `alln teams [--lane code|design|copy|signal] [--json]` — the lane-scoped team
    /// catalog summary (no full prompt templates).
    static func runTeamCatalog(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let lane = opts.value("lane").flatMap(WorkLane.init(rawValue:))
        if let raw = opts.value("lane"), lane == nil {
            fail(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw) (use code|design|copy|signal)")
        }
        let includeInactive = opts.flag("all")
        if opts.flag("json") {
            print(teamsCatalogJSONString(runtime, lane: lane, includeInactive: includeInactive))
        } else {
            let teams = lane.map { runtime.teams.teams(in: $0) } ?? runtime.teams
            let visible = teams.filter { includeInactive || TeamVisibility.isEnabled($0.id) }
            if visible.isEmpty {
                let payload = TeamCatalogJSON.project(teams, lane: lane,
                                                      contractVersion: ContractRegistry.contractVersion,
                                                      includeInactive: includeInactive)
                if let counsel = payload.counsel { print(counsel) }
                for action in payload.nextActions { print("→ \(action.command)") }
            } else {
                for t in visible {
                    let off = TeamVisibility.isEnabled(t.id) ? "" : "\t(inactive)"
                    print("\(t.id)\t\(t.disclosedDisplayName)\t\(t.lane.rawValue)/\(t.outputKind.rawValue)\tdefault \(t.defaultEffort.rawValue)\t\(t.catalogSeatCount) seats\(t.isDefaultForLane ? "\t(default)" : "")\(off)")
                }
            }
        }
    }

    /// The lane-scoped catalog summary JSON for `alln teams --json`. Inactive
    /// (switched-OFF) teams are dropped unless `includeInactive` is true.
    static func teamsCatalogJSONString(_ runtime: ToolRuntime, lane: WorkLane?, includeInactive: Bool = false) -> String {
        let teams = lane.map { runtime.teams.teams(in: $0) } ?? runtime.teams
        return jsonString(TeamCatalogJSON.project(teams, lane: lane,
                                                  contractVersion: ContractRegistry.contractVersion,
                                                  includeInactive: includeInactive))
    }

    /// `alln skills [--lane code|design|copy|signal] [--json]` — lane-scoped skill catalog (no templates).
    static func runSkillCatalog(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let lane = opts.value("lane").flatMap(WorkLane.init(rawValue:))
        if let raw = opts.value("lane"), lane == nil {
            fail(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw) (use code|design|copy|signal)")
        }
        if opts.flag("json") {
            print(skillsCatalogJSONString(lane: lane))
        } else {
            let skills = lane.map { SkillCatalog.list(lane: $0) } ?? WorkLane.allCases.flatMap { SkillCatalog.list(lane: $0) }
            for s in skills {
                print("\(s.id)\t\(s.displayName)\t\(s.lane.rawValue)\t\(s.purpose.rawValue)\(s.builtIn ? "\t(built-in)" : "")")
            }
        }
    }

    /// `alln skills show <skill-id> [--json]` — one skill including template.
    static func runSkillShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills show <skill-id> [--json]")
        }
        guard let skill = SkillCatalog.get(id) else {
            failUnknownSkill(id)
        }
        if opts.flag("json") {
            print(skillShowJSONString(skill))
        } else {
            print("\(skill.id)\t\(skill.displayName)\t\(skill.lane.rawValue)\t\(skill.purpose.rawValue)")
            print(skill.template)
        }
    }

    static func skillsCatalogJSONString(lane: WorkLane?) -> String {
        let skills = lane.map { SkillCatalog.list(lane: $0) }
            ?? WorkLane.allCases.flatMap { SkillCatalog.list(lane: $0) }
        return jsonString(SkillCatalogJSON.project(skills, lane: lane, contractVersion: ContractRegistry.contractVersion))
    }

    static func skillShowJSONString(_ skill: Skill) -> String {
        jsonString(SkillDetailJSON.project(skill, contractVersion: ContractRegistry.contractVersion))
    }

    static func failUnknownTeam(_ id: String) -> Never {
        let lookup = TeamCatalog.all
        if case .failure(let failure) = ExactIdResolver.resolveTeam(id, flag: "--team", teams: lookup) {
            failExactId(failure)
        }
        // Unreachable when catalog is the lookup set; keep a hard fail for safety.
        fail(code: "TEAM_NOT_FOUND", message: "unknown team: \(id)")
    }

    static func failUnknownSkill(_ id: String) -> Never {
        let candidates = WorkLane.allCases.flatMap { SkillCatalog.list(lane: $0) }.map(\.id)
        let suggestions = ErrorDiscovery.nearestMatches(to: id, in: candidates)
        fail(code: "SKILL_NOT_FOUND", message: "unknown skill: \(id)", suggestions: suggestions)
    }

    // MARK: - Catalog mutation (teams)

    /// `alln teams definition <team-id> [--json]` — full TeamPreset for edit/save round-trip.
    static func runTeamsDefinition(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams definition <team-id> [--json]")
        }
        guard let team = TeamCatalog.get(id) else {
            failUnknownTeam(id)
        }
        if opts.flag("json") { print(teamDefinitionJSONString(team)) }
        else { print(teamDefinitionJSONString(team)) }
    }

    /// `alln teams show <team-id> [--json]` — one team with crew, scout, lead, seatCount.
    static func runTeamsShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams show <team-id> [--json]")
        }
        guard let team = TeamCatalog.get(id) else {
            failUnknownTeam(id)
        }
        let show = teamShowProjection(team)
        if opts.flag("json") {
            print(jsonString(show))
        } else {
            print("\(show.id)\t\(show.displayName)\t\(show.lane)/\(show.outputKind)\t\(show.seatCount) seats")
            if let scout = show.scout {
                print("  scout\t\(scout.id)\t\(scout.skillId)\tcount \(scout.count)")
            }
            for row in show.crew {
                print("  crew\t\(row.id)\t\(row.skillId)\tcount \(row.count)\(row.triangulate ? "\ttriangulate" : "")")
            }
            print("  lead\t\(show.lead.skillId)\tcount \(show.lead.count)")
        }
    }

    /// Full `TeamPreset` JSON round-trippable through `teams_save` / `teams edit`.
    static func teamDefinitionJSONString(_ team: TeamPreset) -> String {
        jsonString(team)
    }

    static func teamShowJSONString(_ team: TeamPreset) -> String {
        jsonString(teamShowProjection(team))
    }

    /// Shared inspect projection for text and `--json` `teams show`.
    static func teamShowProjection(_ team: TeamPreset) -> TeamShowJSON {
        TeamShowJSON.project(
            team,
            contractVersion: ContractRegistry.contractVersion,
            origin: teamOrigin(team.id),
            seedId: BuiltInTeams.team(team.id) != nil ? team.id : nil,
            restoreAvailable: TeamCatalog.hasOverride(team.id),
            isDefaultForRun: team.id == "default_chat"
        )
    }

    /// Where the effective team came from: an unedited shipped team (`seed`), the user's
    /// edited version of a shipped team (`override`), or a brand-new team (`custom`).
    static func teamOrigin(_ id: TeamID) -> String {
        if BuiltInTeams.team(id) != nil { return TeamCatalog.hasOverride(id) ? "override" : "seed" }
        return "custom"
    }

    /// `alln teams restore <team-id> [--json]` — revert a team to its shipped version by
    /// removing the user's edits. Idempotent.
    static func runTeamsRestore(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams restore <team-id> [--json]")
        }
        do {
            let result = try TeamCatalog.restore(id)
            if opts.flag("json") {
                print(teamRestoreJSONString(id: id, restored: result.removedOverride))
            } else {
                print(result.removedOverride ? "restored \(id) to shipped version" : "\(id) already at shipped version")
            }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// Restore-acknowledgement JSON for `alln teams restore`.
    static func teamRestoreJSONString(id: TeamID, restored: Bool) -> String {
        struct RestoreAck: Encodable {
            let schemaVersion = 1
            let contractVersion: String
            let id: String
            let restored: Bool
            let origin: String
        }
        return jsonString(RestoreAck(
            contractVersion: ContractRegistry.contractVersion,
            id: id, restored: restored, origin: teamOrigin(id)))
    }

    /// `alln teams duplicate <team-id> [--id <new-id>] [--name <displayName>] [--json]`
    /// JSON is the editable `TeamPreset` (same shape as `teams definition` / `teams edit`).
    static func runTeamsDuplicate(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams duplicate <team-id> [--id <new-id>] [--name <name>] [--json]")
        }
        do {
            let team = try TeamCatalog.duplicateBuiltIn(
                id, name: opts.value("name"), customId: opts.value("id"))
            if opts.flag("json") { print(teamDefinitionJSONString(team)) }
            else {
                print("duplicated \(id) → \(team.id)")
                print("→ alln teams edit \(team.id) --file <path> --json")
            }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln teams new <team-id> --file <path> [--json]` — create a novel custom team
    /// from a supplied TeamPreset. Fails if the id exists or the file id ≠ positional id.
    /// JSON receipt is the editable `TeamPreset` (same shape as `teams definition` / `teams edit`).
    /// No `teams create` alias.
    static func runTeamsNew(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams new <team-id> --file <path> [--json]")
        }
        do {
            let team = try loadTeamDefinition(from: opts.value("file"), expectedId: id, verb: "new")
            let created = try TeamCatalog.createNew(team)
            if opts.flag("json") { print(teamDefinitionJSONString(created)) }
            else { print("created \(created.id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln teams edit <team-id> [--file <path>] [--json]` — full replacement save.
    /// JSON receipt is the editable `TeamPreset` that was persisted (round-trippable).
    static func runTeamsEdit(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams edit <team-id> [--file <path>] [--json]")
        }
        guard TeamCatalog.get(id) != nil else {
            failUnknownTeam(id)
        }
        do {
            let team = try loadTeamDefinition(from: opts.value("file"), expectedId: id, verb: "edit")
            try TeamCatalog.saveCustom(team)
            if opts.flag("json") { print(teamDefinitionJSONString(team)) }
            else { print("saved \(team.id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln teams set-default <team-id> [--json]`
    static func runTeamsSetDefault(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams set-default <team-id> [--json]")
        }
        do {
            let team = try TeamCatalog.setDefault(id)
            if opts.flag("json") { print(teamShowJSONString(team)) }
            else { print("default for \(team.lane.rawValue) → \(team.id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln teams delete <team-id> [--json]`
    static func runTeamsDelete(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams delete <team-id> [--json]")
        }
        do {
            try TeamCatalog.deleteCustom(id)
            if opts.flag("json") { print(jsonString(DeleteAck(deleted: id))) }
            else { print("deleted \(id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    static func loadTeamDefinition(from path: String?, expectedId: TeamID, verb: String = "edit") throws -> TeamPreset {
        guard let path else {
            throw CatalogError.teamInvalid("--file is required for teams \(verb)")
        }
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        if let envelope = try? CoreJSON.decode(CatalogEnvelope<TeamPreset>.self, from: data) {
            guard envelope.definition.id == expectedId else {
                throw CatalogError.teamInvalid("file team id \(envelope.definition.id) does not match \(expectedId)")
            }
            return envelope.definition
        }
        if let showShapeError = teamShowProjectionRefusal(data) {
            throw CatalogError.teamInvalid(showShapeError)
        }
        let team: TeamPreset
        do {
            team = try CoreJSON.decode(TeamPreset.self, from: data)
        } catch let error as DecodingError {
            // Surface as TEAM_INVALID (agent fixes the file) rather than
            // INTERNAL_ERROR (agent retries verbatim and loops forever).
            throw CatalogError.teamInvalid(describeTeamDecodingError(error))
        }
        guard team.id == expectedId else {
            throw CatalogError.teamInvalid("file team id \(team.id) does not match \(expectedId)")
        }
        return team
    }

    /// `teams show` / `set-default` project `crew`/`seatCount`; authoring accepts only
    /// `TeamPreset` (`agentSpecs`). Refuse the show shape by name so agents don't
    /// loop on a decode that can never succeed.
    static func teamShowProjectionRefusal(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let hasShowMarkers = obj["crew"] != nil || obj["seatCount"] != nil
        let hasEditableSpec = obj["agentSpecs"] != nil
        guard hasShowMarkers, !hasEditableSpec else { return nil }
        return "expected TeamPreset shape (agentSpecs + lead); got a teams show projection — use `alln teams definition <id> --json` or the JSON from teams duplicate/new/edit"
    }

    /// Translates a `TeamPreset` JSON `DecodingError` into an agent-actionable
    /// message naming the exact JSON field path, instead of letting the raw
    /// Swift `DecodingError` description (internal type names, `CodingKeys`
    /// noise) leak into the CLI's error envelope.
    static func describeTeamDecodingError(_ error: DecodingError) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            var result = ""
            for key in codingPath {
                if let index = key.intValue {
                    result += "[\(index)]"
                } else if result.isEmpty {
                    result = key.stringValue
                } else {
                    result += ".\(key.stringValue)"
                }
            }
            return result
        }
        func describe(_ type: Any.Type) -> String {
            switch type {
            case is String.Type: return "string"
            case is Bool.Type: return "boolean"
            case is Int.Type, is Int8.Type, is Int16.Type, is Int32.Type, is Int64.Type,
                 is UInt.Type, is UInt8.Type, is UInt16.Type, is UInt32.Type, is UInt64.Type,
                 is Double.Type, is Float.Type:
                return "number"
            default: return "\(type)"
            }
        }
        switch error {
        case .keyNotFound(let key, let context):
            let base = path(context.codingPath)
            let field = base.isEmpty ? key.stringValue : "\(base).\(key.stringValue)"
            return "team definition missing required field '\(field)'"
        case .valueNotFound(let type, let context):
            return "team definition field '\(path(context.codingPath))' must be a \(describe(type)), found null"
        case .typeMismatch(let type, let context):
            return "team definition field '\(path(context.codingPath))' must be a \(describe(type))"
        case .dataCorrupted(let context):
            let base = path(context.codingPath)
            return base.isEmpty
                ? "team definition is not valid JSON: \(context.debugDescription)"
                : "team definition field '\(base)' is invalid: \(context.debugDescription)"
        @unknown default:
            return "team definition could not be decoded: \(error)"
        }
    }

    // MARK: - Catalog mutation (skills)

    /// `alln skills duplicate <skill-id> [--name <displayName>] [--json]`
    static func runSkillsDuplicate(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills duplicate <skill-id> [--name <name>] [--json]")
        }
        do {
            let skill = try SkillCatalog.duplicateBuiltIn(id, name: opts.value("name"))
            if opts.flag("json") { print(skillShowJSONString(skill)) }
            else { print("duplicated \(id) → \(skill.id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln skills new --lane <lane> --name <name> --purpose <purpose> [--template-file <path>] [--json]`
    static func runSkillsNew(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let laneRaw = opts.value("lane"), let lane = WorkLane(rawValue: laneRaw) else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills new --lane code|design|copy|signal --name <name> --purpose answer|review|planWriter [--template-file <path>] [--json]")
        }
        guard let name = opts.value("name"), !name.isEmpty else {
            fail(code: "CLI_USAGE_ERROR", message: "--name is required")
        }
        guard let purposeRaw = opts.value("purpose"), let purpose = SkillPurpose(rawValue: purposeRaw) else {
            fail(code: "CLI_USAGE_ERROR", message: "--purpose must be answer, review, or planWriter")
        }
        let template: String
        do { template = try loadTemplateText(opts.value("template-file")) }
        catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
        do {
            let skill = try SkillCatalog.createCustom(lane: lane, name: name, purpose: purpose, template: template)
            if opts.flag("json") { print(skillShowJSONString(skill)) }
            else { print("created \(skill.id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln skills edit <skill-id> [--name <displayName>] [--template-file <path>] [--json]`
    static func runSkillsEdit(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills edit <skill-id> [--name <name>] [--template-file <path>] [--json]")
        }
        guard var skill = SkillCatalog.get(id) else {
            failUnknownSkill(id)
        }
        if let name = opts.value("name") { skill.displayName = name }
        do {
            if let path = opts.value("template-file") { skill.template = try loadTemplateText(path) }
            try SkillCatalog.saveEffective(skill)
            guard let saved = SkillCatalog.get(id) else { failUnknownSkill(id) }
            if opts.flag("json") { print(skillShowJSONString(saved)) }
            else { print("saved \(saved.id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln skills restore <skill-id> [--json]` — revert a built-in skill to its shipped seed.
    static func runSkillsRestore(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills restore <skill-id> [--json]")
        }
        do {
            let result = try SkillCatalog.restore(id)
            let origin = SkillCatalog.origin(of: id)?.rawValue ?? "seed"
            if opts.flag("json") {
                print(jsonString(SkillRestoreJSON(
                    contractVersion: ContractRegistry.contractVersion,
                    id: id, restored: result.removedOverride, origin: origin
                )))
            } else {
                print(result.removedOverride
                      ? "restored \(id) to shipped version"
                      : "\(id) already at shipped version")
            }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln skills gc [--json]` — delete custom skills not referenced by any team.
    static func runSkillsGC(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        do {
            let deleted = try SkillCatalog.purgeUnreferencedCustomSkills()
            if opts.flag("json") {
                print(jsonString(SkillGCAck(deleted: deleted, count: deleted.count)))
            } else if deleted.isEmpty {
                print("no unreferenced custom skills")
            } else {
                print("deleted \(deleted.count) unreferenced custom skill(s)")
                for id in deleted { print(id) }
            }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln skills delete <skill-id> [--json]`
    static func runSkillsDelete(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills delete <skill-id> [--json]")
        }
        do {
            try SkillCatalog.deleteCustom(id)
            if opts.flag("json") { print(jsonString(DeleteAck(deleted: id))) }
            else { print("deleted \(id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    static func loadTemplateText(_ path: String?) throws -> String {
        guard let path else { return "You are a helpful specialist for this lane." }
        return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    struct DeleteAck: Encodable {
        let schemaVersion = 1
        let deleted: String
    }

    struct SkillGCAck: Encodable {
        let schemaVersion = 1
        let deleted: [String]
        let count: Int
    }

    /// Shared readiness check for `run --dry-run` (and any other free twin).
    static func preflight(_ runtime: ToolRuntime, args: [String: Any]) -> TeamPreflight.Result {
        var result = TeamPreflight.preflight(
            teams: runtime.teams,
            lane: (args["lane"] as? String).flatMap(WorkLane.init(rawValue:)),
            teamId: args["team"] as? String,
            type: args["type"] as? String,
            effort: (args["effort"] as? String).flatMap(EffortLevel.init(rawValue:)),
            readyModels: runtime.readyModels)
        if result.canStart {
            switch runtime.governor.availability() {
            case .available:
                break
            case .busy:
                let reason = "busy: \(runtime.config.maxConcurrentTeamRuns) team runs already running"
                result.canStart = false
                result.blockedReason = reason
                result.warnings.append("Team governor is at capacity.")
                result.nextAction = .retryLater(teamId: result.teamPresetId)
            case .unavailable(let reason):
                result.canStart = false
                result.blockedReason = reason
                result.warnings.append("Team governor slot store is unavailable.")
                result.nextAction = .runDoctor
            }
        }
        return result
    }


    /// `alln team cancel <run-id> --json`
    static func runTeamCancel(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard opts.flag("json"), let runId = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln team cancel <run-id> --json\n".utf8))
            exit(2)
        }
        guard let response = await runtime.asyncTeamService().cancel(runId: runId) else {
            emitRunNotFound(runId, "no run matches \(runId)", in: await runtime.asyncTeamService().runStore)
            exit(1)
        }
        print(jsonString(response))
    }

    /// `alln team reconcile [run-id] [--all-projects] --json` — explicit
    /// ownership reconcile (PO-S01 v2). Identity-dead owners are PG-killed
    /// (recorded pgid only) and stamped `endReason: reconciledOrphan`. An exact
    /// run-id may target any project; the bare sweep is scoped to the caller's
    /// canonical project root (Concurrent Invocation Isolation F1) — machine-wide
    /// only via the explicit `--all-projects`.
    static func runTeamReconcile(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard opts.flag("json") else {
            FileHandle.standardError.write(Data("usage: alln team reconcile [run-id] [--all-projects] --json\n".utf8))
            exit(2)
        }
        let runId = opts.positional.first
        let scopeRoot = opts.flag("all-projects") ? nil : FileManager.default.currentDirectoryPath
        let reaped = await runtime.asyncTeamService().reconcile(runId: runId, scopeRoot: scopeRoot)
        print(jsonString(TeamReconcileResponse(reaped: reaped.map {
            .init(runId: $0.id, status: $0.status.rawValue, endReason: $0.endReason?.rawValue)
        })))
    }

    /// `alln continuity receipt [--json]` — local observed-facts summary of
    /// vendor waits covered and automatic resumes (last 24 hours).
    static func runContinuity(_ args: [String]) {
        let opts = Options(args)
        guard args.first == "receipt" else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln continuity receipt [--json]")
        }
        let until = Date()
        let since = until.addingTimeInterval(-24 * 60 * 60)
        let receipt = MorningReceipt.project(runs: RunStore().list(), since: since, until: until)
        if opts.flag("json") {
            print(jsonString(receipt))
        } else {
            print(receipt.humanSummary)
        }
    }

    /// `alln ps [--all] [--all-projects] [--json]` — ownership inventory with
    /// reconcile-on-read (CLP-S02). Default shows alive + needs-action only;
    /// `--all` includes terminal history.
    static func runOwnershipPs(_ args: [String]) async {
        let opts = Options(args)
        let allProjects = opts.flag("all-projects")
        let includeHistory = opts.flag("all")
        let scopeRoot = allProjects ? nil : FileManager.default.currentDirectoryPath
        let envelope = ProcessOwnershipSurface(runStore: RunStore()).list(
            scopeRoot: scopeRoot, includeHistory: includeHistory
        )
        if opts.flag("json") {
            print(jsonString(envelope))
        } else {
            print(ProcessOwnershipSurface.humanTable(envelope))
            if !allProjects {
                print("(project scope: \(FileManager.default.currentDirectoryPath) — `alln ps --all-projects` for the fleet view)")
            }
            if !includeHistory {
                print("(`alln ps --all` for terminal/history rows)")
            }
        }
    }

    /// `alln gc [--json]` — safely prune old dead terminal run/relay records.
    static func runOwnershipGC(_ args: [String]) {
        let opts = Options(args)
        let dryRun = opts.flag("dry-run")
        let result = ProcessOwnershipGarbageCollector(dryRun: dryRun).collect()
        if opts.flag("json") {
            print(jsonString(result))
            return
        }
        let verb = dryRun ? "would prune" : "pruned"
        let suffix = dryRun ? "  (dry run — nothing deleted)" : ""
        print("\(verb) \(result.prunedCount) of \(result.consideredCount) ownership record(s)\(suffix)")
        print("kept alive: \(result.keptAlive.count)")
        print("kept non-terminal: \(result.keptNonTerminal.count)")
        print("kept within retention: \(result.keptWithinRetention.count)")
        print("kept thread-referenced: \(result.keptThreadReferenced.count)")
        print("kept unreadable: \(result.keptUnreadable.count)")
        print("kept after removal failure: \(result.keptRemovalFailed.count)")
    }

    /// `alln kill <id> | --all [--all-projects] [--json]` — identity-checked
    /// total group kill + terminal `endReason: killed` (PO-S05). Refuses on
    /// identity mismatch. `--all` is scoped to the caller's project root
    /// (Concurrent Invocation Isolation F1); `--all-projects` makes it the
    /// explicit machine-wide fleet kill. An exact id may target any project.
    static func runOwnershipKill(_ args: [String]) async {
        let opts = Options(args)
        let asJSON = opts.flag("json")
        let surface = ProcessOwnershipSurface(runStore: RunStore())
        let killAll = opts.flag("all")
        let result: OwnershipKillJSON

        if killAll {
            let scopeRoot = opts.flag("all-projects") ? nil : FileManager.default.currentDirectoryPath
            result = surface.killAll(scopeRoot: scopeRoot)
        } else if let id = opts.positional.first {
            switch surface.kill(id: id) {
            case .success(let row):
                result = .init(killed: [row])
            case .failure(.notFound):
                fail(code: "OWNERSHIP_NOT_FOUND", message: "no owned process tree matches \(id)")
            case .failure(.alreadyTerminal(_, let end)):
                fail(code: "OWNERSHIP_ALREADY_TERMINAL", message: "\(id) is already terminal\(end.map { " (endReason=\($0))" } ?? "")")
            case .failure(.identityMismatch):
                fail(code: "OWNERSHIP_IDENTITY_MISMATCH", message: "refusing to signal \(id): recorded identity does not match the live process")
            }
        } else {
            FileHandle.standardError.write(Data("usage: alln kill <id> | --all [--all-projects] [--json]\n".utf8))
            exit(2)
        }

        if asJSON { print(jsonString(result)); return }
        if killAll {
            print("killed \(result.killedCount) process tree(s)")
            for row in result.killed { print("  \(row.id) (\(row.kind)) endReason=\(row.endReason ?? "-") killOutcome=\(row.killOutcome ?? "-") signalled=\(row.signalled)") }
            for skip in result.skipped { print("  skip \(skip.id): \(skip.reason)") }
        } else if let row = result.killed.first {
            let outcome = row.killOutcome.map { " killOutcome=\($0)" } ?? ""
            print("kill \(row.id) (\(row.kind)) endReason=\(row.endReason ?? "-")\(outcome) signalled=\(row.signalled)")
        }
    }

    /// `alln docs [topic] [--errors] [--schema] [--examples]` — the generated,
    /// agent-facing reference, projected from the contract registry.
    static func runDocs(_ args: [String]) {
        let opts = Options(args)
        let reg = ContractRegistry.milestone1
        if opts.flag("errors") {
            print("# Error codes\n")
            for e in reg.errors {
                print("## \(e.code) (\(e.ruleId))\n- requiresManual: \(e.requiresManual) · retryable: \(e.retryable)\n- action: \(e.agentAction)\n- \(e.explain)\n")
            }
            return
        }
        if opts.flag("schema") {
            print((try? ContractSchema.json(ContractSchema.teamRunSchema())) ?? "{}")
            print((try? ContractSchema.json(ContractSchema.doctorResultSchema())) ?? "{}")
            return
        }
        if opts.flag("examples") {
            print("# Example recipes\n")
            for ex in reg.examples { print("- `\(ex.id)` — \(ex.title): `\(ex.command)`") }
            return
        }
        if let topic = opts.positional.first {
            switch TypedRef.resolveDocsTopic(topic, registry: reg) {
            case .helpMarkdown(let markdown):
                print(markdown)
            case .commands(let cmds):
                for c in cmds {
                    print("### alln \(c.name)\n\(c.summary)")
                    print(CommandProjection.markdownCommandBody(c), terminator: "")
                    print("")
                }
            case .nearMiss(let query, let suggestions):
                fail(
                    code: "CLI_USAGE_ERROR",
                    message: "no docs for topic: \(query)",
                    suggestions: suggestions
                )
            case .notFound(let query, let suggestions):
                let hint: String
                if let parsed = TypedRef.parse(query), parsed.kind != .command {
                    hint = "; use `alln menu show \(query) --json`"
                } else {
                    hint = ""
                }
                fail(
                    code: "CLI_USAGE_ERROR",
                    message: "no docs for topic: \(query)\(hint)",
                    suggestions: suggestions
                )
            }
            return
        }
        print(ContractDocs.markdown(reg))
    }

    /// Resolves a run reference (`latest` or an id) for `alln show`.
    static func resolveRun(_ ref: String) -> TeamRun? {
        if ref == "latest" { return RunStore().list().max(by: { $0.createdAt < $1.createdAt }) }
        return loadRun(ref)
    }

    /// Query-style verbs (show, spec, floor show) accept `run`; team lifecycle verbs use `runId`.
    /// Accept both keys defensively to prevent silent "latest" drift when callers mix conventions.
    static func runRef(from args: [String: Any]) -> String {
        let ref = (args["run"] as? String) ?? (args["runId"] as? String)
        if let ref, !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ref.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "latest"
    }

    /// Resolve the registered project for cwd: walk to git root, match
    /// `normalizedRootPath` (AE-S05). Returns nil when the root is unregistered.
    static func resolveProjectFromCwd(
        store: ProjectStore,
        cwd: String = FileManager.default.currentDirectoryPath
    ) -> Project? {
        let gitRoot = GitObserver().repoTopLevel(forPath: cwd) ?? RootNormalization.normalize(cwd).key
        return resolveProject(gitRoot, store: store)
    }

    /// Workspace `git rev-parse HEAD` from cwd (AE-S08), or nil outside a checkout.
    static func workspaceHeadGitSha(
        cwd: String = FileManager.default.currentDirectoryPath
    ) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["-C", cwd, "rev-parse", "HEAD"]
        task.environment = AllnighterSpawnEnvironmentPolicy.processEnvironment()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty == false) ? s : nil
        } catch {
            return nil
        }
    }

    /// Resolve a project token (id or repo-root path) to a Project. One SSOT for the
    /// run entrypoints — `alln run` and the team engine resolve the same way.
    static func resolveProject(_ token: String, store: ProjectStore) -> Project? {
        if let byId = try? store.get(token) { return byId }
        let key = RootNormalization.normalize(token).key
        return (try? store.activeProjects())?.first { $0.normalizedRootPath == key }
    }

    /// Resolve a thread reference (`latest` or an id) to a concrete thread id, or nil if no
    /// thread matches. One SSOT for `thread send` / `thread rename`.
    static func resolveThreadId(_ ref: String, store: ThreadStore) -> String? {
        if ref == "latest" { return store.list().first?.id }
        return store.get(ref) != nil ? ref : nil
    }

    /// Default projection context for a persisted run (reproduce command and
    /// artifact materialization from the run's own catalog facts). Writes the
    /// polished HTML artifact when the run is terminal so `--json` carries
    /// `artifact.path`.
    ///
    /// `ownerState` is supplied by the read path that reconciled identity
    /// (`showReadPath`); the mapper never probes processes.
    /// Journal paths stay on disk only — never projected into public TeamRunJSON
    /// (ORS-S03c: no public filesystem escape hatch).
    static func defaultRunContext(
        _ run: TeamRun,
        full: Bool = false,
        models: [Model] = [],
        manifests: [DriverManifest] = [],
        ownerState: TeamRunJSON.Observation.OwnerState = .unknown
    ) -> TeamRunJSONMapper.Context {
        let store = RunStore()
        let runDir = try? store.runDirectory(forRunId: run.id)
        let pmTurn = pmTurnProjection(for: run, store: store)
        let repro = reproduceCommand(run)
        let artifactPath: String? = {
            guard let runDir else { return nil }
            return TeamRunJSONMapper.materializeArtifactPath(
                for: run,
                runDirectory: runDir,
                reproduceCommand: repro,
                models: models,
                manifests: manifests
            )
        }()
        return .init(
            reproduceCommand: repro,
            includeWorkerPromptSnapshots: full,
            runDirectory: runDir,
            pmTurn: pmTurn.pmTurn,
            pmTurnNotes: pmTurn.notes,
            artifactPath: artifactPath,
            ownerState: ownerState
        )
    }

    /// ORS-S01b: one `alln show` read path — reconcile ownership, then resolve
    /// `ownerState` from recorded identity only (never activity / status).
    ///
    /// Calls `reconcileRun` **without** `recoverTerminalLiveOwnership: true`.
    /// That flag is cancel-lie recovery only; defaulting it on previously made a
    /// bare read surface TERM→SIGKILL live recorded trees. `show` declares
    /// `destructive: never` / `workerStart: never` and must never signal.
    static func showReadPath(
        run: TeamRun,
        models: [Model],
        store: RunStore = RunStore()
    ) -> (run: TeamRun, ownerState: TeamRunJSON.Observation.OwnerState) {
        // Default recoverTerminalLiveOwnership is false — never pass true here.
        let reconciled = store.reconcileRun(runId: run.id, models: models) ?? run
        let dir = try? store.runDirectory(forRunId: reconciled.id)
        let identity = dir.flatMap { ProcessOwnership.readOwnerIdentity(in: $0) }
        let ownerState: TeamRunJSON.Observation.OwnerState =
            identity.map { ProcessOwnership.isIdentityAlive($0) ? .alive : .dead } ?? .unknown
        return (reconciled, ownerState)
    }

    /// The CLI owns attaching a durable PM receipt to a projected terminal run.
    static func pmTurnProjection(for run: TeamRun, store: RunStore) -> PMTurnStatusProjection {
        PMTurnStatusProjection.load(
            kind: .run,
            subjectId: run.id,
            atPMBoundary: run.status.isTerminal,
            store: PMTurnStore(runsRootDirectory: store.rootDirectory)
        )
    }

    /// The Floor projection JSON for a persisted run, for `alln floor show`.
    static func floorRunJSONString(_ run: TeamRun) -> String {
        let journalPath = (try? RunStore().runDirectory(forRunId: run.id))?
            .appendingPathComponent("run.json").path
        let floor = FloorProjector.project(
            run, reproduceCommand: reproduceCommand(run),
            runJournalPath: journalPath, traceId: "trace_\(run.id)")
        return jsonString(floor)
    }

    /// `alln floor show <run-id|latest> [--json]` — the inspectable Floor for one
    /// team run: worker lanes, durable artifacts, typed return, timeline, and
    /// Execute requirements.
    static func runFloorShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let ref = opts.positional.first ?? "latest"
        guard let run = resolveRun(ref) else {
            failRunNotFound(ref == "latest" ? nil : ref, "no run matches \(ref)")
        }
        if opts.flag("json") {
            print(floorRunJSONString(run))
        } else {
            let floor = FloorProjector.project(run)
            print("Floor \(run.id) · \(floor.run.status.rawValue) · \(floor.run.family ?? "?")")
            for lane in floor.workerLanes {
                print("  \(lane.purpose.rawValue)\t\(lane.agentId)\t\(lane.status)")
            }
            if let ret = floor.floorReturn { print("\nReturn (\(ret.kind.rawValue)): \(ret.title)") }
        }
    }

    /// `alln show <run-id|latest> [--json | --stream | --answer] [--full]` — show one run.
    static func runShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let ref = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln show <run-id|latest> [--json | --stream | --answer] [--full]\n".utf8)); exit(2)
        }
        guard let resolved = resolveRun(ref) else {
            failRunNotFound(ref == "latest" ? nil : ref, "no run matches \(ref)")
        }
        // One read path for both --json and human: reconcile, then owner identity.
        let prepared = showReadPath(run: resolved, models: runtime.models)
        let run = prepared.run
        let ownerState = prepared.ownerState
        let context = defaultRunContext(
            run, full: opts.flag("full"),
            models: runtime.models, manifests: runtime.registry.all,
            ownerState: ownerState
        )
        let trj = TeamRunJSONMapper.map(
            run, models: runtime.models, manifests: runtime.registry.all,
            context: context
        )
        if opts.flag("answer") {
            // QDR-S01 recovery path: the durable answer text alone, stdout clean
            // enough to redirect into a file. Partials are labeled on stderr, and
            // a run with no text fails loud instead of printing silence.
            guard let retrieval = answerRetrieval(from: trj) else {
                fail(
                    code: "RUN_NO_ANSWER",
                    message: "run \(run.id) has no answer text (status \(run.status.rawValue))"
                )
            }
            if let note = retrieval.note {
                FileHandle.standardError.write(Data("\(note)\n".utf8))
            }
            print(retrieval.text)
            return
        }
        if opts.flag("stream") {
            // ORS-S02b2: reattach READ surface — snapshot + bounded replay + live
            // follow + one terminal or attention-required boundary. Disposable observer.
            let outcome = runShowStream(
                run: run,
                teamRunJSON: trj,
                store: RunStore(),
                models: runtime.models,
                manifests: runtime.registry.all
            )
            if outcome.exitCode != 0 {
                if let code = outcome.errorCode {
                    emitFailure(code: code, message: outcome.message ?? "show stream failed")
                }
                exit(Int32(outcome.exitCode))
            }
            return
        }
        if opts.flag("json") {
            print(jsonString(trj))
        } else {
            // Same mapped truth as --json (including observation.ownerState).
            print("Run \(run.id) · \(run.status.rawValue)")
            print(run.prompt)
            if let md = trj.answer?.markdown, !md.isEmpty {
                print("\n\(md)")
            } else if let first = trj.answers.lazy.compactMap(\.markdown).first(where: { !$0.isEmpty }) {
                print("\n\(first)")
            } else if !run.warnings.isEmpty {
                // A run with no answer is not a run with nothing to say: a refused
                // hand-off carries its reason here, and this is the command the
                // hand-off tells the caller to come back to.
                print("\n\(run.warnings.joined(separator: "\n"))")
            }
            if let path = context.artifactPath {
                print("\nArtifact: \(path)")
                print("Open:     alln artifact show \(run.id)")
            }
        }
    }

    /// ORS-S02b2 test/production hooks for the live-follow loop.
    ///
    /// Production uses real wall time + sleep. Tests inject a fake clock, a
    /// short budget, and cooperative cancel so observer death is proven without
    /// hanging the suite. Cancelling the observer must never signal or settle
    /// the run (disposable observer).
    struct ShowStreamFollowControl {
        var now: () -> Date = { Date() }
        /// Sleep between journal polls. Production: `Thread.sleep`. Tests: no-op
        /// or clock advance only.
        var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
        /// Cooperative cancel for the disposable observer (never propagates to the run).
        var isCancelled: () -> Bool = { false }
        /// Override derived observer budget (seconds). `nil` → derive from run wall / 7200.
        var observerBudgetSeconds: TimeInterval? = nil
        /// Journal poll cadence (seconds).
        var pollIntervalSeconds: TimeInterval = 0.25
        /// Invoked once per follow poll (tests append events / settle mid-follow).
        var onPoll: (() -> Void)? = nil
    }

    /// ORS-S02b2: `alln show <id> --stream` — immediate snapshot, bounded replay,
    /// live follow of new durable events, exactly one terminal frame **or** a
    /// bounded attention-required exit. Exit class for terminal is the run's
    /// terminal class (unconditional).
    ///
    /// Read-only and disposable: never signals, kills, settles, or writes run
    /// state; never passes `recoverTerminalLiveOwnership: true` (caller must use
    /// `showReadPath` / plain `reconcileRun` first). Cancelling the observer task
    /// only stops following — the run is untouched.
    ///
    /// Injected `writeLine` / `follow` keep framing unit-testable without a process pipe.
    @discardableResult
    static func runShowStream(
        run: TeamRun,
        teamRunJSON: TeamRunJSON,
        store: RunStore = RunStore(),
        models: [Model] = [],
        manifests: [DriverManifest] = [],
        journal: RemoteRunEventJournal? = nil,
        writeLine: @escaping (String) -> Void = { print($0) },
        follow: ShowStreamFollowControl = ShowStreamFollowControl()
    ) -> RunCLI.StreamOutcome {
        let journal = journal ?? RemoteRunEventJournal(rootDirectory: store.rootDirectory)

        // (a) ONE immediate snapshot — every lifecycle state, including queued.
        // Replay completeness is known only after reading history; we rewrite the
        // snapshot line only when incomplete (still the first frame consumers see
        // when collecting — see collect path). Practically: read history first,
        // then emit snapshot with the honest marker.
        // (b) Bounded recent durable activity. Gaps are normal (global per-Mac
        // seq). Unparseable lines are skipped. Journal trouble NEVER aborts —
        // ORS-P0-DEGRADE founder ruling. Terminal truth comes from RunStore.
        let historyRead: RemoteRunEventRead
        do {
            historyRead = try journal.eventsRead(forRunId: run.id)
        } catch {
            // File-level failure: degrade to empty history, continue.
            historyRead = RemoteRunEventRead(events: [], skippedUnparseableLines: 1)
        }
        let history = Array(historyRead.events.suffix(NDJSONStreamProjector.streamReplayMaxEvents))
        let replayIncomplete = historyRead.isIncomplete

        writeLine(NDJSONStreamProjector.snapshotLine(
            teamRunId: run.id, teamRun: teamRunJSON, replayIncomplete: replayIncomplete
        ))

        let historySeqs = history.map { Int($0.seq) }

        // Replay non-terminal lines only. Terminal delivery is owned below so the
        // frame carries TeamRunJSON + pmTurn and remains exactly one.
        let attachment = NDJSONStreamProjector.NDJSONAttachment()
        let nonTerminalHistory = history.filter { event in
            guard let mapped = NDJSONStreamProjector.LiveMapper().event(for: event) else {
                return true // unmapped kinds drop later; keep for seq bookkeeping
            }
            return !NDJSONStreamProjector.terminalEventNames.contains(mapped.event)
        }
        for line in attachment.replayLines(nonTerminalHistory) {
            writeLine(line)
        }

        // (c) Already terminal → exactly ONE terminal frame, then exit with the
        // run's terminal exit class (unconditional; no --exit-status opt-in).
        if run.status.isTerminal {
            return emitTerminalDelivery(
                run: run,
                teamRunJSON: teamRunJSON,
                history: history,
                historySeqs: historySeqs,
                writeLine: writeLine
            )
        }

        // (d) Live follow until terminal, attention-required, observer budget
        // (terminalOnly only), or observer cancel. Disposable: no run writes.
        return followLive(
            initialRun: run,
            initialJSON: teamRunJSON,
            store: store,
            models: models,
            manifests: manifests,
            journal: journal,
            afterSeq: Int64(historySeqs.last ?? 0),
            attachment: attachment,
            writeLine: writeLine,
            follow: follow
        )
    }

    // MARK: - show --stream live follow (ORS-S02b2)

    private static func emitTerminalDelivery(
        run: TeamRun,
        teamRunJSON: TeamRunJSON,
        history: [RunEvent],
        historySeqs: [Int],
        writeLine: (String) -> Void
    ) -> RunCLI.StreamOutcome {
        let terminalSeq: Int = {
            let mapper = NDJSONStreamProjector.LiveMapper()
            if let lastTerm = history.last(where: {
                guard let m = mapper.event(for: $0) else { return false }
                return NDJSONStreamProjector.terminalEventNames.contains(m.event)
            }) {
                return Int(lastTerm.seq)
            }
            return (historySeqs.last ?? 0) + 1
        }()
        writeLine(NDJSONStreamProjector.terminalDeliveryLine(
            teamRunId: run.id,
            teamRun: teamRunJSON,
            seq: terminalSeq
        ))
        return RunCLI.StreamOutcome(
            exitCode: Int(RunCLI.exitCode(for: run)),
            errorCode: nil,
            message: nil
        )
    }

    /// Drain non-terminal live lines, then emit exactly one terminal delivery frame.
    private static func finishWithTerminal(
        run: TeamRun,
        models: [Model],
        manifests: [DriverManifest],
        store: RunStore,
        journal: RemoteRunEventJournal,
        lastSeq: inout Int64,
        attachment: NDJSONStreamProjector.NDJSONAttachment,
        writeLine: @escaping (String) -> Void
    ) -> RunCLI.StreamOutcome {
        let prepared = showReadPath(run: run, models: models, store: store)
        let currentJSON = mapShowStreamJSON(
            run: prepared.run,
            ownerState: prepared.ownerState,
            models: models,
            manifests: manifests,
            store: store
        )
        let mapper = NDJSONStreamProjector.LiveMapper()
        if let drained = try? journal.events(forRunId: run.id, after: lastSeq) {
            for event in drained {
                lastSeq = max(lastSeq, event.seq)
                // Skip journal terminal kinds — delivery frame below is the one terminal.
                if let mapped = mapper.event(for: event),
                   NDJSONStreamProjector.terminalEventNames.contains(mapped.event) {
                    continue
                }
                if let line = attachment.liveLine(for: event) {
                    writeLine(line)
                }
            }
        }
        let termHistory = (try? journal.events(forRunId: run.id)) ?? []
        return emitTerminalDelivery(
            run: prepared.run,
            teamRunJSON: currentJSON,
            history: termHistory,
            historySeqs: termHistory.map { Int($0.seq) },
            writeLine: writeLine
        )
    }

    private static func followLive(
        initialRun: TeamRun,
        initialJSON: TeamRunJSON,
        store: RunStore,
        models: [Model],
        manifests: [DriverManifest],
        journal: RemoteRunEventJournal,
        afterSeq: Int64,
        attachment: NDJSONStreamProjector.NDJSONAttachment,
        writeLine: @escaping (String) -> Void,
        follow: ShowStreamFollowControl
    ) -> RunCLI.StreamOutcome {
        var lastSeq = afterSeq
        var currentJSON = initialJSON
        let activityMode = initialJSON.observation.activityMode
        let applyObserverBudget = activityMode == .terminalOnly || activityMode == .unknown
        let budgetSeconds = follow.observerBudgetSeconds
            ?? NDJSONStreamProjector.streamObserverBudgetSeconds(for: initialRun)
        let followStartedAt = follow.now()
        let pollInterval = max(0.01, follow.pollIntervalSeconds)

        // Immediate attention check (attach while already blocked) — exit promptly.
        if let outcome = attentionExitIfNeeded(
            run: initialRun,
            teamRunJSON: currentJSON,
            lastSeq: lastSeq,
            writeLine: writeLine
        ) {
            return outcome
        }

        while true {
            if follow.isCancelled() {
                // Disposable observer: cancel stops following only. No signal, no
                // settle, no run write, no terminal fabrication.
                return .success
            }

            follow.onPoll?()

            // Fresh run truth from store (read-only; never recoverTerminalLiveOwnership).
            let loaded = store.load(runId: initialRun.id) ?? initialRun
            if loaded.status.isTerminal {
                return finishWithTerminal(
                    run: loaded,
                    models: models,
                    manifests: manifests,
                    store: store,
                    journal: journal,
                    lastSeq: &lastSeq,
                    attachment: attachment,
                    writeLine: writeLine
                )
            }

            if let outcome = attentionExitIfNeeded(
                run: loaded,
                teamRunJSON: {
                    let prepared = showReadPath(run: loaded, models: models, store: store)
                    currentJSON = mapShowStreamJSON(
                        run: prepared.run,
                        ownerState: prepared.ownerState,
                        models: models,
                        manifests: manifests,
                        store: store
                    )
                    return currentJSON
                }(),
                lastSeq: lastSeq,
                writeLine: writeLine
            ) {
                return outcome
            }

            // Live durable events after the replay window (no `replayed` key).
            // Terminal journal kinds are never live-emitted here — exactly one
            // terminal frame is owned by `finishWithTerminal` / terminalDeliveryLine
            // (carries full TeamRunJSON + pmTurn).
            // ORS-P0-DEGRADE: journal read failures degrade to empty fresh set —
            // never abort; terminal still comes from RunStore.
            let fresh: [RunEvent]
            do {
                fresh = try journal.events(forRunId: initialRun.id, after: lastSeq)
            } catch {
                fresh = []
            }
            let mapper = NDJSONStreamProjector.LiveMapper()
            var sawTerminalJournalEvent = false
            for event in fresh {
                if follow.isCancelled() { return .success }
                lastSeq = max(lastSeq, event.seq)
                if let mapped = mapper.event(for: event),
                   NDJSONStreamProjector.terminalEventNames.contains(mapped.event) {
                    sawTerminalJournalEvent = true
                    continue
                }
                if let line = attachment.liveLine(for: event) {
                    writeLine(line)
                }
            }
            if sawTerminalJournalEvent {
                let settled = store.load(runId: initialRun.id) ?? loaded
                if settled.status.isTerminal {
                    return finishWithTerminal(
                        run: settled,
                        models: models,
                        manifests: manifests,
                        store: store,
                        journal: journal,
                        lastSeq: &lastSeq,
                        attachment: attachment,
                        writeLine: writeLine
                    )
                }
            }

            // terminalOnly / unknown: finite observer budget. Incremental: never.
            if applyObserverBudget {
                let elapsed = follow.now().timeIntervalSince(followStartedAt)
                if elapsed >= budgetSeconds {
                    return emitObserverBudgetAttention(
                        run: loaded,
                        teamRunJSON: currentJSON,
                        lastSeq: lastSeq,
                        writeLine: writeLine
                    )
                }
            }

            follow.sleep(pollInterval)
        }
    }

    /// Map a reloaded run for stream frames without process-probing in the mapper.
    private static func mapShowStreamJSON(
        run: TeamRun,
        ownerState: TeamRunJSON.Observation.OwnerState,
        models: [Model],
        manifests: [DriverManifest],
        store: RunStore
    ) -> TeamRunJSON {
        let runDir = try? store.runDirectory(forRunId: run.id)
        let pmTurn = pmTurnProjection(for: run, store: store)
        let context = TeamRunJSONMapper.Context(
            reproduceCommand: "alln show \(run.id)",
            runDirectory: runDir,
            pmTurn: pmTurn.pmTurn,
            pmTurnNotes: pmTurn.notes,
            ownerState: ownerState
        )
        return TeamRunJSONMapper.map(
            run, models: models, manifests: manifests, context: context
        )
    }

    /// Sourced blocker or vendor wait → attention frame + non-showRun recovery.
    private static func attentionExitIfNeeded(
        run: TeamRun,
        teamRunJSON: TeamRunJSON,
        lastSeq: Int64,
        writeLine: (String) -> Void
    ) -> RunCLI.StreamOutcome? {
        guard let cause = attentionCause(for: run) else { return nil }
        let next = recoveryNextAction(for: cause, runId: run.id)
        let message: String
        switch cause {
        case .sourcedBlocker:
            message = "run is waiting on a sourced blocker; stream ends at attention-required boundary"
        case .vendorWait:
            message = "run is waiting on vendor capacity; stream ends at attention-required boundary"
        case .observerBudget:
            // unreachable here — budget has its own emitter
            message = "observer budget expired"
        }
        writeLine(NDJSONStreamProjector.attentionRequiredLine(
            teamRunId: run.id,
            teamRun: teamRunJSON,
            reason: cause,
            message: message,
            seq: Int(lastSeq) + 1,
            silenceExpected: false,
            nextAction: next
        ))
        return .success
    }

    private static func emitObserverBudgetAttention(
        run: TeamRun,
        teamRunJSON: TeamRunJSON,
        lastSeq: Int64,
        writeLine: (String) -> Void
    ) -> RunCLI.StreamOutcome {
        // PM ruling (ORS-S03e, One_Run_Surface.md — founder review at closeout):
        // the only honest recovery for "observe again" would be showRun /
        // re-stream — circular, banned. Emit NO nextAction; silenceExpected.
        // Silence is expected on terminalOnly; never fabricated as stuck.
        let message =
            "observer budget expired on terminalOnly driver; silence is expected until settlement"
        writeLine(NDJSONStreamProjector.attentionRequiredLine(
            teamRunId: run.id,
            teamRun: teamRunJSON,
            reason: .observerBudget,
            message: message,
            seq: Int(lastSeq) + 1,
            silenceExpected: true,
            nextAction: nil
        ))
        return .success
    }

    private static func attentionCause(for run: TeamRun) -> NDJSONStreamProjector.AttentionReason? {
        if let blocker = run.blocker {
            switch blocker.resource {
            case .vendorBackoff:
                return .vendorWait
            case .repoWriteLock, .teamGovernor, .driverCapacity, .permission:
                return .sourcedBlocker
            }
        }
        if run.phase == .waitingForVendor {
            return .vendorWait
        }
        if run.phase == .waitingForWriteLock {
            return .sourcedBlocker
        }
        return nil
    }

    /// Recovery nextAction per attention cause. Never `showRun`.
    private static func recoveryNextAction(
        for cause: NDJSONStreamProjector.AttentionReason,
        runId: String
    ) -> TeamRunJSON.NextAction? {
        switch cause {
        case .sourcedBlocker:
            // Holder / FIFO ticket surface (same command as inspectBlocker catalog).
            return TeamRunJSON.NextAction(
                kind: .inspectBlocker,
                command: "alln ps --json",
                label: "Inspect write-lock holder / sourced blocker"
            )
        case .vendorWait:
            // Capacity / driver surface — not a stream reattach.
            return TeamRunJSON.NextAction(
                kind: .inspectBlocker,
                command: "alln capacity --json",
                label: "Inspect vendor capacity / driver wait"
            )
        case .observerBudget:
            // No honest non-circular recovery — omit nextAction (spec tension).
            return nil
        }
    }

    /// `alln spec [<run-id>|latest] [--detail summary|full|artifactRefsOnly] [--json]`
    /// — retrieve a run's spec/result packet.
    static func runSpec(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let ref = opts.positional.first ?? "latest"
        guard let run = resolveRun(ref) else {
            failRunNotFound(ref == "latest" ? nil : ref, "no run matches \(ref)")
        }
        let result = specResult(run, runtime: runtime, detail: opts.value("detail"))
        if opts.flag("json") { print(jsonString(result)) }
        else {
            print(result.summary)
            if let full = result.full, !full.isEmpty { print("\n\(full)") }
            if !result.warnings.isEmpty { print("\nWarnings:"); for w in result.warnings { print("  ⚠︎ \(w)") } }
        }
    }

    /// Project a persisted run into a `SpecRetrieval.Result`.
    static func specResult(_ run: TeamRun, runtime: ToolRuntime, detail: String?) -> SpecRetrieval.Result {
        let journalPath = (try? RunStore().runDirectory(forRunId: run.id))?.appendingPathComponent("run.json").path
        return SpecRetrieval.project(
            run: run, models: runtime.models,
            detail: detail.flatMap(SpecRetrieval.Detail.init(rawValue:)) ?? .summary,
            artifactRefs: journalPath.map { [$0] } ?? [])
    }

    /// `alln export <run-id|latest> --format md` — export the result bundle.
    static func runExport(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let ref = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln export <run-id|latest> --format md\n".utf8)); exit(2)
        }
        let format = opts.value("format") ?? "md"
        guard format == "md" else {
            fail(code: "CLI_USAGE_ERROR", message: "unsupported export format: \(format) (only md)")
        }
        guard let run = resolveRun(ref) else {
            failRunNotFound(ref == "latest" ? nil : ref, "no run matches \(ref)")
        }
        let dir = try? RunStore().runDirectory(forRunId: run.id)
        let bundle = dir.flatMap {
            try? String(contentsOf: $0.appendingPathComponent("bundle.md"), encoding: .utf8)
        }
        print(exportMarkdown(
            for: run,
            models: runtime.models,
            manifests: runtime.registry.all,
            existingBundle: bundle
        ))
    }

    /// VSI-S05 export body. Prefer a durable partial over a stale prompt-first
    /// `bundle.md` — that precedence is exactly why the incident export returned
    /// prompt-only text while 26k chars of work lived only in a watcher buffer.
    static func exportMarkdown(
        for run: TeamRun,
        models: [Model],
        manifests: [DriverManifest],
        existingBundle: String?
    ) -> String {
        let trj = TeamRunJSONMapper.map(
            run, models: models, manifests: manifests, context: .init()
        )
        if let answer = trj.answer,
           let md = answer.markdown, !md.isEmpty,
           answer.status != .done {
            return "# \(run.id)\n\n# Partial answer\n\n\(md)"
        }
        if let existingBundle, !existingBundle.isEmpty {
            return existingBundle
        }
        let body = humanAnswer(for: run, models: models, manifests: manifests)
            ?? "(no answer)"
        return "# \(run.id)\n\n\(run.prompt)\n\n\(body)"
    }

    /// `alln doctor explain <code> [--json]` — explain one registry error code.
    /// `alln doctor handoff [--json]` — can this terminal get work run by the app?
    ///
    /// Costs no quota and starts no worker: it drops one `ping` in the mailbox and
    /// reports what was observed. Deliberately separate from `alln doctor`, which
    /// must stay a read-only report — this one enqueues something.
    static func runDoctorHandoff(_ args: [String]) async {
        let opts = Options(args)
        let store = ProjectStore()
        let repoRoot = resolveProjectFromCwd(store: store)?.localRootPath
            ?? FileManager.default.currentDirectoryPath
        let report = await HandoffDoctor().check(
            contractVersion: ContractRegistry.contractVersion, repoRoot: repoRoot)
        if opts.flag("json") {
            print(jsonString(report))
        } else {
            print("hand-off: \(report.verdict.rawValue) (\(report.waitedMs)ms)")
            print(report.detail)
            print("check id: \(report.runId)")
        }
        if !report.isHealthy { exit(1) }
    }

    /// `alln doctor silence [--json]` — mine run journals for idle-timeout histograms
    /// (IDLE-HF-S04 telemetry). Read-only; spends no quota.
    static func runDoctorSilence(_ args: [String]) {
        let opts = Options(args)
        let report = RunJournalSilenceTelemetry.mine(runStore: RunStore())
        if opts.flag("json") {
            print(jsonString(report))
        } else {
            print("idle timeouts: \(report.idleTimeoutCount) / \(report.scannedRuns) scanned runs")
            for driver in report.byDriver {
                print("\(driver.driverId): \(driver.idleTimeoutCount)")
                for bucket in driver.buckets {
                    print("  \(bucket.label): \(bucket.count)")
                }
            }
        }
    }

    static func runDoctorExplain(_ args: [String]) {
        let opts = Options(args)
        guard let code = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln doctor explain <code> [--json]\n".utf8)); exit(2)
        }
        guard let spec = ContractRegistry.milestone1.errors.first(where: { $0.code == code }) else {
            fail(code: "CLI_USAGE_ERROR", message: "unknown error code: \(code)")
        }
        let bridged = ErrorHelpBridge.explain(spec, contractVersion: ContractRegistry.contractVersion)
        if opts.flag("json") {
            print(jsonString(bridged))
        } else {
            print("\(spec.code)  (\(spec.ruleId))")
            print("  requiresManual: \(spec.requiresManual) · retryable: \(spec.retryable)")
            print("  action: \(spec.agentAction)")
            print("  \(spec.explain)")
            if let ref = bridged.helpRef { print("  help: \(ref)") }
        }
    }

    /// `alln version [--json]` / `alln --version` — binary + contract + build identity.
    static func runVersion(_ args: [String]) {
        let opts = Options(args)
        let binaryPath = ProcessOwnership.currentExecutablePath()
            ?? CommandLine.arguments.first
        let payload = VersionJSON(
            binaryVersion: binaryVersion,
            gitSha: AllnighterBuildInfo.gitSha,
            buildTime: AllnighterBuildInfo.buildTime,
            binaryPath: binaryPath,
            update: menuUpdate(now: Date())
        )
        if opts.flag("json") {
            print(jsonString(payload))
        } else {
            var line = "alln \(payload.binaryVersion) (contract \(payload.contractVersion), hash \(payload.contractHash.prefix(12))…"
            if let sha = payload.gitSha, sha != "unknown", !sha.isEmpty {
                line += ", git \(sha.prefix(12))"
            }
            line += ")"
            print(line)
            if let update = payload.update {
                FileHandle.standardError.write(
                    Data("update available: \(update.current) → \(update.latest); \(update.command)\n".utf8)
                )
            }
        }
    }

    /// `alln update [--check] [--json]` — soft-announce only (BQ-4). Never
    /// downloads or execs; applying is the human/agent running the one-liner.
    static func runUpdate(_ args: [String]) {
        let opts = Options(args)
        // V1: bare `update` and `update --check` are the same read-only path.
        _ = opts.flag("check")
        let binaryPath = ProcessOwnership.currentExecutablePath()
            ?? CommandLine.arguments.first
        let info = menuUpdate(now: Date())
        if opts.flag("json") {
            if let info {
                print(jsonString(info))
            } else {
                // Quiet when nothing to announce — same omit-key policy as menu.
                struct EmptyUpdate: Encodable {
                    let schemaVersion = 1
                    let available = false
                    let current: String
                    let command: String
                }
                print(jsonString(EmptyUpdate(
                    current: binaryVersion,
                    command: ReleaseChannel.installCommand
                )))
            }
            return
        }
        print("alln \(binaryVersion)")
        if let info {
            print("latest \(info.latest)")
            print("update: \(info.command)")
        } else {
            print("latest (none announced)")
            print("install/repair: \(ReleaseChannel.installCommand)")
        }
        if let binaryPath {
            print("binary \(binaryPath)")
        }
    }

    /// `alln bootstrap [--host claude|cursor|codex|generic|hermes|openclaw] [--json]` —
    /// the activation surface that replaced `alln mcp install` (docs/phases/
    /// MCP_Retirement.md §Activation). Prints, never writes: same consent
    /// posture as the retired MCP install.
    static func runBootstrap(_ args: [String]) {
        let opts = Options(args)
        let hostArg = opts.value("host") ?? "generic"
        guard let host = Bootstrap.Host(argument: hostArg) else {
            fail(code: "CLI_USAGE_ERROR", message: "unknown host: \(hostArg) (use claude|cursor|codex|generic|hermes|openclaw)")
        }
        let ctx = Bootstrap.liveContext()
        if opts.flag("json") {
            print(Bootstrap.jsonString(
                host: host,
                binaryPath: ctx.binaryPath,
                onPath: ctx.onPath,
                capacity: menuCapacity(now: Date())
            ))
        } else {
            print(Bootstrap.render(host: host, binaryPath: ctx.binaryPath, onPath: ctx.onPath))
        }
    }

    static func runInstallCLI(_ args: [String]) {
        let opts = Options(args)
        let request = InstallCLI.Request(
            argv0: CommandLine.arguments.first,
            pathOverride: opts.value("path"),
            printOnly: opts.flag("print"),
            pathEnvironment: ProcessInfo.processInfo.environment["PATH"]
        )
        switch InstallCLI.run(request) {
        case .printed(let json):
            if opts.flag("json") {
                print(jsonString(json))
            } else {
                let target = json.target ?? "alln"
                let installDir = request.pathOverride
                    ?? InstallCLI.defaultInstallDirectory(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
                print(InstallCLI.printInstructions(target: target, installDir: installDir))
            }
        case .installed(let json):
            let refresh = ServeLifecycle().refreshAfterInstall()
            if opts.flag("json") {
                print(jsonString(json))
            } else {
                print(InstallCLI.humanLine(json))
            }
            if refresh.outcome == .failed {
                FileHandle.standardError.write(Data("install-cli: \(refresh.detail)\n".utf8))
            }
        case .failed(let code, let message):
            fail(code: code, message: message)
        }
    }

    /// AE-S01: top-level help is a pure projection of `ContractRegistry` — no hand-written rows.
    static func helpText() -> String {
        CLIUsage.topLevelHelpText()
    }

    static func printHelp() {
        print(helpText())
    }

    static func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? CoreJSON.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Canonical human result text from the TeamRunJSON answer projection.
    /// Falls back to seat markdown only when no canonical answer exists (partial multi-seat).
    /// Non-success single-worker partials are labeled `Partial answer` (VSI-S05).
    static func humanAnswer(
        for run: TeamRun,
        models: [Model],
        manifests: [DriverManifest]
    ) -> String? {
        let trj = TeamRunJSONMapper.map(
            run, models: models, manifests: manifests,
            context: .init()
        )
        if let answer = trj.answer, let md = answer.markdown, !md.isEmpty {
            if answer.status != .done {
                return "Partial answer\n\n\(md)"
            }
            return md
        }
        return trj.answers.lazy
            .compactMap(\.markdown)
            .first { !$0.isEmpty }
    }

    /// QDR-S01: `--answer` retrieval body from a mapped run. The stdout text is
    /// raw (redirect-clean); `note` carries the stderr label when the text is a
    /// durable partial or a seat fallback rather than a canonical done answer.
    /// Nil when the record holds no answer text at all — the caller fails loud.
    static func answerRetrieval(from trj: TeamRunJSON) -> (text: String, note: String?)? {
        if let answer = trj.answer, let md = answer.markdown, !md.isEmpty {
            if answer.status != .done {
                return (md, "note: partial answer — answer status \(answer.status.rawValue)")
            }
            return (md, nil)
        }
        if let first = trj.answers.lazy.compactMap(\.markdown).first(where: { !$0.isEmpty }) {
            return (first, "note: no canonical answer — printing the first seat's text")
        }
        return nil
    }

    /// One compact, single-line JSON object — the house law for any `--json` command that
    /// streams progress (FR8): every stdout line, including the final envelope, must
    /// parse independently. Single-envelope commands keep `jsonString` (pretty).
    static func jsonLine<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Loads tool config + builds a `TeamService` from `DefaultConfig` (+ `Config/`
/// overrides when present).
struct ToolRuntime {
    let models: [Model]
    let registry: DriverRegistry
    let teams: [TeamPreset]
    let config: ToolConfig
    /// Cached per-driver invocations from the last detection (health == runs).
    let invocations: [String: ToolInvocation]
    let governor: TeamGovernor
    let asyncTeam: AsyncTeamService
    private let readyModelsOverride: [Model]?

    init() {
        let registry = DefaultConfig.registry
        let models = ModelCatalog.resolvedModels(registry: registry)
        let teams = TeamCatalog.all
        let config = ToolRuntime.loadConfig()
        var invs: [String: ToolInvocation] = [:]
        let records = SetupStore().load().records
        for record in records {
            guard let inv = record.invocation else { continue }
            invs[record.driverId] = inv
            if let command = registry.manifest(id: record.driverId)?.invoke?.command, !command.isEmpty {
                invs[command] = inv
            }
        }
        self.models = models
        self.registry = registry
        self.teams = teams
        self.config = config
        self.invocations = invs
        let governor = TeamGovernor(capacity: config.maxConcurrentTeamRuns)
        self.governor = governor
        self.asyncTeam = AsyncTeamService(models: models, registry: registry, teams: teams, config: config, governor: governor, invocations: invs)
        self.readyModelsOverride = nil
    }

    /// Injected runtime for CLI handler tests (isolated async team store).
    init(
        models: [Model],
        registry: DriverRegistry,
        teams: [TeamPreset],
        config: ToolConfig,
        invocations: [String: ToolInvocation] = [:],
        asyncTeam: AsyncTeamService,
        readyModels: [Model],
        governor: TeamGovernor? = nil
    ) {
        self.models = models
        self.registry = registry
        self.teams = teams
        self.config = config
        self.invocations = invocations
        self.governor = governor ?? TeamGovernor(capacity: config.maxConcurrentTeamRuns)
        self.asyncTeam = asyncTeam
        self.readyModelsOverride = readyModels
    }

    func service() -> TeamService {
        TeamService(models: models, registry: registry, teams: teams, config: config, governor: governor, invocations: invocations)
    }

    func asyncTeamService() -> AsyncTeamService { asyncTeam }

    /// The ready bench: enabled models whose source probe is ready **and** whose
    /// driver is not capacity-cooling from recent failed runs. Missing setup is
    /// unknown, not ready; cooling Claude/Codex/etc. must not look "ready" in
    /// preflight just because a stale smoke said the binary was found.
    var readyModels: [Model] {
        if let readyModelsOverride { return readyModelsOverride }
        let records = SetupStore().load().records
        let parked = SetupStore().load().parkedSet
        let observations = BenchReadiness.recentObservations(from: RunStore().list())
        let cooling = BenchReadiness.coolingDriverIds(observations: observations)
        return BenchReadiness.readyModels(
            models: models,
            probeRecords: records,
            coolingDriverIds: cooling,
            parkedDriverIds: parked,
            knownDriverIds: Set(registry.all.map(\.id))
        )
    }

    private static func loadConfig() -> ToolConfig {
        let url = AllnighterPaths.config.appendingPathComponent("Tool/config.json")
        if let data = try? Data(contentsOf: url), let cfg = try? CoreJSON.decode(ToolConfig.self, from: data) { return cfg }
        return ToolConfig()
    }

}

/// Tiny argv parser: positionals + `--key value` + `--flag`.
/// Repeatable value flags (`seat`, and thread `image`/`ref`) preserve order.
struct Options {
    /// Boolean flags never consume the next token as a value, so
    /// `alln team --json "prompt"` keeps "prompt" as the positional.
    /// Derived from M1 `FlagSpec.takesValue == false` — never a parallel hand list
    /// (AE code-audit: FlagSpec is the choke point for flag shape).
    static let booleanFlags: Set<String> = ContractRegistry.booleanFlagNames()
    /// Flags whose repeated occurrences each contribute one ordered value (RSO-S01).
    static let orderedRepeatableFlags: Set<String> = ["seat", "image", "ref"]
    var positional: [String] = []
    var values: [String: String] = [:]
    var repeatedValues: [String: [String]] = [:]
    var flags: Set<String> = []
    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if Self.booleanFlags.contains(key) {
                    flags.insert(key); i += 1
                } else if i + 1 < args.count && !args[i + 1].hasPrefix("--") {
                    let value = args[i + 1]
                    if Self.orderedRepeatableFlags.contains(key) {
                        repeatedValues[key, default: []].append(value)
                    } else {
                        values[key] = value
                    }
                    i += 2
                } else {
                    flags.insert(key); i += 1
                }
            } else { positional.append(a); i += 1 }
        }
        // Last single value wins for ordinary flags; repeatable flags also mirror the last.
        for (key, ordered) in repeatedValues {
            if let last = ordered.last {
                values[key] = last
            }
        }
    }
    func value(_ key: String) -> String? { values[key] }
    func valuesList(_ key: String) -> [String] { repeatedValues[key] ?? [] }
    func flag(_ key: String) -> Bool { flags.contains(key) }
}
