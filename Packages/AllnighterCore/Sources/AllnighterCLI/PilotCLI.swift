import Foundation
import AllnighterCore
import AllnighterEngine
#if canImport(Darwin)
import Darwin
#endif

/// Pilot engine (`docs/archive/phases/Pilot_Relay.md`, superseded by
/// `docs/archive/phases/Loop_Verb_Cutover.md`): this session is the PM, Allnighter
/// runs the crew (dev seat + rails). Same substrate as `RelayCLI`/`RelayCoordinator` —
/// `RelayCoordinator.startPilot`/`runExternalRound` do all the work; this file is a
/// thin CLI-shaped projection, mirroring `RelayCLI`'s throwing, store-injectable,
/// exit-free `parse*` helpers so the recovery ladder is unit-testable without a
/// subprocess.
///
/// `pair pilot` no longer dispatches here (LVC Piece 1, hard cutover) — `LoopCLI`
/// calls the surviving entry points directly (`runStart(request:...)`, `runWatch`,
/// `runAdopt`) as `alln loop`'s internal engine. CLI is the only agent surface
/// (`docs/archive/phases/MCP_Retirement.md` — MCP is retired).
enum PilotCLI {
    /// Resolved `pilot start` inputs after flag parsing, alias resolution, and optional recall.
    struct StartRequest {
        var config: RelayCoordinator.Config
        var devModelId: String
        /// The raw `--dev-model` token when it differed from the resolved model id.
        var devWorkerAlias: String?
        var rememberedDevWorker: Bool
    }

    // MARK: - start

    /// LVC-S02b: `alln loop start --pm caller` (`LoopCLI`) builds a `StartRequest`
    /// itself — with `config.docPath: nil` for a brief-only loop — and dispatches
    /// straight through, without going through `parseStartConfig`'s hard `--doc`
    /// requirement (that requirement is `parseStartConfig`'s own contract, kept for
    /// its direct unit tests; nothing live calls it anymore).
    static func runStart(request: StartRequest, opts: Options, runtime: ToolRuntime) async {
        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        switch coordinator.startPilot(config: request.config) {
        case .success(let state):
            let scaffoldPath: String
            do {
                scaffoldPath = try PilotHandoverScaffold.writeRoundFile(relayId: state.id, round: 1)
            } catch {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not write handover scaffold: \(error)")
            }
            do {
                try PilotDevSeatStore().save(projectId: request.config.projectId ?? "", devModelId: request.devModelId)
            } catch {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not remember dev seat: \(error)")
            }
            emitStartResult(
                state,
                devModelId: request.devModelId,
                devWorkerAlias: request.devWorkerAlias,
                rememberedDevWorker: request.rememberedDevWorker,
                scaffoldPath: scaffoldPath,
                json: opts.flag("json")
            )
        case .failure(.untilNotSupported):
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "--until is not supported for pilot start — Pilot has no clock; each round advances only when you call `pilot handoff`."
            )
        }
    }

    static func parseStartConfig(
        _ args: [String],
        projectStore: ProjectStore = ProjectStore(),
        models: [Model] = [],
        probeRecords: [ToolProbeRecord] = [],
        devSeatStore: PilotDevSeatStore = PilotDevSeatStore()
    ) throws -> StartRequest {
        let opts = Options(args)
        guard let docPath = opts.value("doc") else { throw PilotCLIError.missingRequired("--doc <path>") }
        guard let projectToken = opts.value("project") else { throw PilotCLIError.missingRequired("--project <id|path>") }
        guard let project = projectStore.resolveFresh(projectToken) else {
            throw PilotCLIError.projectNotFound(projectToken)
        }
        guard let maxRounds = RelayCLI.parseMaxRounds(opts.value("max-rounds")) else {
            throw PilotCLIError.invalidMaxRounds(opts.value("max-rounds") ?? "")
        }
        // PO-F7: reuses PO-F5's `alln run --idle-timeout` parse helper — no second idle system.
        let idleParsed = RunCLI.parseIdleTimeoutSeconds(opts.value("idle-timeout"))
        if let error = idleParsed.error { throw PilotCLIError.invalidIdleTimeout(error) }

        let catalogModels = models.isEmpty ? ModelCatalog.resolvedModels(registry: DefaultConfig.registry) : models
        let records = probeRecords
        let parked = SetupStore().load().parkedSet
        let readySeats = PilotSeatResolver.readySeats(
            from: catalogModels, probeRecords: records, parkedDriverIds: parked
        )

        let devModelId: String
        let devWorkerAlias: String?
        let remembered: Bool
        if let token = opts.value("dev-model") {
            switch PilotSeatResolver.resolve(alias: token, models: catalogModels) {
            case .success(let resolved):
                devModelId = resolved
                // Exact-id only — alias echo is retired (MR-S04).
                devWorkerAlias = nil
                remembered = false
            case .failure(.ambiguous(let alias, let candidates)):
                throw PilotCLIError.ambiguousDevWorker(
                    alias: alias,
                    candidates: PilotSeatResolver.formatCandidates(candidates)
                )
            case .failure(.noMatch(let alias, _)):
                throw PilotCLIError.devWorkerNotFound(
                    alias: alias,
                    readySeats: PilotSeatResolver.formatReadySeats(readySeats)
                )
            case .failure(.exactId(let failure)):
                throw PilotCLIError.devWorkerNotFound(
                    alias: failure.provided,
                    readySeats: PilotSeatResolver.formatReadySeats(readySeats)
                )
            case .failure(.noReadySeats):
                throw PilotCLIError.noReadyDevSeats
            }
        } else if let rememberedId = devSeatStore.load(projectId: project.id)?.devModelId {
            devModelId = rememberedId
            devWorkerAlias = nil
            remembered = true
        } else {
            throw PilotCLIError.missingDevWorker(
                readySeats: PilotSeatResolver.formatReadySeats(readySeats)
            )
        }

        let config = RelayCoordinator.Config(
            projectRoot: project.normalizedRootPath,
            projectId: project.id,
            docPath: docPath,
            pmModelId: RelayState.callerPMModelId,
            devModelId: devModelId,
            maxRounds: maxRounds,
            devTurnIdleTimeoutSeconds: idleParsed.value
        )
        return StartRequest(
            config: config,
            devModelId: devModelId,
            devWorkerAlias: devWorkerAlias,
            rememberedDevWorker: remembered
        )
    }

    // MARK: - handoff
    //
    // The raw-args `pilot handoff` CLI entry point is deleted (`pair pilot` no
    // longer dispatches here, Piece 1). `LoopCLI.runStep` (`alln loop step`) is
    // the live equivalent — it calls `parseHandoffSubmission`'s sibling
    // `synthesizeSubmission` and `RelayCoordinator.runExternalRound` directly, and
    // shares `emitHandoffResult`/`failPilotRound` below. The parse helpers here
    // stay: they're exercised directly by `PilotCLITests`.

    /// Resolves a `pilot handoff` submission: the legacy `--file`/stdin path (markdown +
    /// RelayVerdict tail) or the frictionless `--verdict` + `--handover-file`/`--handover-stdin`
    /// path that synthesizes the tail internally (`docs/phases/Pilot_Polish_And_Agent_UX.md` P1).
    static func parseHandoffSubmission(_ opts: Options) throws -> String {
        let hasFile = opts.value("file") != nil
        let hasHandoverFile = opts.value("handover-file") != nil
        let hasHandoverStdin = opts.flag("handover-stdin")
        let hasVerdict = opts.value("verdict") != nil

        if hasFile && (hasHandoverFile || hasHandoverStdin || hasVerdict) {
            throw PilotCLIError.mutuallyExclusive("--file", "--handover-file/--handover-stdin/--verdict")
        }
        if hasHandoverFile && hasHandoverStdin {
            throw PilotCLIError.mutuallyExclusive("--handover-file", "--handover-stdin")
        }

        if hasHandoverFile || hasHandoverStdin || hasVerdict {
            return try synthesizeSubmissionFromFlags(opts)
        }
        return try readLegacySubmission(opts)
    }

    /// Legacy path: the round's full markdown from `--file`, or stdin when omitted.
    static func readLegacySubmission(_ opts: Options) throws -> String {
        let text: String
        if let path = opts.value("file") {
            guard let contents = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
                throw PilotCLIError.fileUnreadable(path)
            }
            text = contents
        } else {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            text = String(decoding: data, as: UTF8.self)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PilotCLIError.noSubmission
        }
        return text
    }

    /// Reads handover prose for the frictionless path (`--handover-file` or `--handover-stdin`).
    static func readHandoverText(_ opts: Options) throws -> String {
        let text: String
        if let path = opts.value("handover-file") {
            guard let contents = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
                throw PilotCLIError.fileUnreadable(path)
            }
            text = contents
        } else {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            text = String(decoding: data, as: UTF8.self)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PilotCLIError.noHandover
        }
        return text
    }

    private static func synthesizeSubmissionFromFlags(_ opts: Options) throws -> String {
        guard let verdictRaw = opts.value("verdict") else {
            throw PilotCLIError.missingRequired("--verdict continue|done|escalate")
        }
        guard let verdict = RelayVerdict.Verdict(rawValue: verdictRaw) else {
            throw PilotCLIError.invalidVerdict(verdictRaw)
        }

        let note = opts.value("note")
        var handover: String?
        if opts.value("handover-file") != nil || opts.flag("handover-stdin") {
            handover = try readHandoverText(opts)
        }

        if verdict == .continueRelay {
            guard let handover, !handover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PilotCLIError.missingRequired("--handover-file <path> or --handover-stdin")
            }
        }

        return try synthesizeSubmission(verdict: verdict, handover: handover, note: note)
    }

    /// Builds the markdown `runExternalRound` expects: optional prose + a trailing fenced
    /// RelayVerdict block. The dev seat receives `handover` byte-exact from the verdict JSON.
    static func synthesizeSubmission(
        verdict: RelayVerdict.Verdict, handover: String?, note: String?
    ) throws -> String {
        let relayVerdict = RelayVerdict(verdict: verdict, handover: handover, note: note)
        let json = String(decoding: try CoreJSON.encode(relayVerdict), as: UTF8.self)
        let tail = "```json\n\(json)\n```"
        if let handover, !handover.isEmpty {
            return handover + "\n\n" + tail
        }
        return tail
    }

    /// Legacy alias kept for existing tests.
    static func readSubmission(_ opts: Options) throws -> String {
        try readLegacySubmission(opts)
    }

    private static func loadedProjectRoot(_ relayId: String, stateStore: RelayStateStore) -> String? {
        stateStore.load(id: relayId)?.projectRoot
    }

    /// Launch configuration for `--no-wait` detached `pilot handoff`.
    ///
    /// Works Test intent: bare `alln` from PATH on a clean checkout — no `<cwd>/alln`
    /// symlink masking a broken argv0 spawn.
    struct DetachedHandoffLaunch: Equatable {
        var executableURL: URL
        var currentDirectoryURL: URL
    }

    enum DetachedHandoffLaunchError: Error, Equatable {
        case relayNotFound(String)
        case missingProjectRoot(String)
        case unresolvedExecutable
    }

    static func detachedHandoffLaunch(
        relayId: String,
        stateStore: RelayStateStore,
        argv0: String? = CommandLine.arguments.first,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        currentExecutablePath: () -> String? = ProcessOwnership.currentExecutablePath
    ) throws -> DetachedHandoffLaunch {
        switch stateStore.loadResult(id: relayId) {
        case .success(let state):
            guard !state.projectRoot.isEmpty else {
                throw DetachedHandoffLaunchError.missingProjectRoot(relayId)
            }
            let executablePath = ProcessOwnership.resolveRunningExecutablePath(
                argv0: argv0,
                pathEnvironment: pathEnvironment,
                currentExecutablePath: currentExecutablePath
            )
            guard let executablePath else {
                throw DetachedHandoffLaunchError.unresolvedExecutable
            }
            return DetachedHandoffLaunch(
                executableURL: URL(fileURLWithPath: executablePath),
                currentDirectoryURL: URL(fileURLWithPath: state.projectRoot)
            )
        case .failure(.notFound):
            throw DetachedHandoffLaunchError.relayNotFound(relayId)
        case .failure(.decodeFailed(let detail)):
            AllnighterCLI.fail(
                code: "RELAY_STATE_DECODE_FAILED",
                message: detail.agentMessage,
                supportDir: AllnighterCLI.effectiveSupportDir()
            )
        }
    }

    // The `--no-wait` background-dispatch path that used to live here
    // (`dispatchHandoffInBackground`, called only from the now-deleted raw-args
    // `pilot handoff`) is gone with it — `alln loop step` has no `--no-wait` in the
    // locked LVC v7 grammar (§2), so there is nothing left to re-target it at.
    // `detachedHandoffLaunch` below stays: `PilotCLITests` exercises it directly.

    /// Not `private` — `LoopCLI.runStep` (`alln loop step`, LVC-S02d) shares this
    /// exact print path with `pilot handoff`.
    static func emitHandoffResult(_ payload: RelayCoordinator.PilotRoundResult, json: Bool) {
        let relayJSON = RelayJSON.project(payload.state, contractVersion: ContractRegistry.contractVersion)
        if json {
            print(AllnighterCLI.jsonLine(PilotHandoffJSON(relay: relayJSON, devReport: payload.devReport)))
        } else {
            print(RelayDispatch.humanRelaySummary(relayJSON))
            if let devReport = payload.devReport {
                print("\n----- dev report (round \(relayJSON.rounds)) -----\n\(devReport)")
            }
            let log = RelayDispatch.humanRoundLog(relayJSON)
            if !log.isEmpty { print("\n" + log) }
            print("\n" + nextActionLine(for: payload.state))
        }
        if payload.state.status == .escalated || payload.state.status == .stopped { exit(1) }
    }

    // MARK: - status

    /// How a `.running` relay should be recovered — productizes detached-handoff survival
    /// vs orphan reconciliation (`Pilot_DX.md` §DX5).
    enum InFlightRecovery: Equatable {
        case none
        case handoffAlive
        case orphanReconciled
    }

    /// Loads relay state, optionally reconciling a dead-owner `.running` relay.
    static func loadRelayState(
        relayId: String,
        stateStore: RelayStateStore,
        threadProjector: RelayThreadProjector?,
        reconcileOrphans: Bool
    ) -> (state: RelayState, recovery: InFlightRecovery)? {
        let base: RelayState
        switch stateStore.loadResult(id: relayId) {
        case .success(let loaded):
            base = loaded
        case .failure(.notFound):
            return nil
        case .failure(.decodeFailed(let detail)):
            AllnighterCLI.fail(
                code: "RELAY_STATE_DECODE_FAILED",
                message: detail.agentMessage,
                supportDir: AllnighterCLI.effectiveSupportDir()
            )
        }
        var state = base
        guard state.status == .running else { return (state, .none) }
        if stateStore.isOwnerDead(id: relayId) {
            if reconcileOrphans {
                state = RelayCoordinator.reconcileOrphan(
                    state, stateStore: stateStore, threadProjector: threadProjector, now: Date.init
                )
            }
            return (state, .orphanReconciled)
        }
        return (state, .handoffAlive)
    }

    // The raw-args `pilot status` CLI entry point (and its `parseStatusWait`
    // validator) is deleted along with it (`pair pilot` no longer dispatches here,
    // Piece 1) — `alln loop status` is `RelayCLI.runStatus`, a separate, chair-
    // neutral implementation (§2). `makeStatusJSON`/`recoveryActionLine`/
    // `recoveryNextActions`/`statusNextActions` below stay: they're exercised
    // directly by tests as the `PilotStatusJSON` builder.

    // MARK: - watch

    /// Non-TTY agents get a bounded wait so piped `pilot watch` does not block forever.
    static let defaultNonTTYMaxWaitSeconds: TimeInterval = 1_800

    /// Heartbeat cadence while a round is `.running` — keeps silent hosts from reaping.
    static let watchHeartbeatSeconds: TimeInterval = 15.0

    /// Set by SIGTERM/SIGINT handlers; polled between sleeps (PLT-S04).
    final class WatchInterruptFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var interrupted = false

        func fire() {
            lock.lock()
            interrupted = true
            lock.unlock()
        }

        var isInterrupted: Bool {
            lock.lock()
            defer { lock.unlock() }
            return interrupted
        }
    }

    enum WatchEndReason: Equatable {
        case interrupted
        case maxWaitExpired
    }

    /// Resolves `--max-wait`: explicit flag wins; non-TTY stdout gets
    /// `defaultNonTTYMaxWaitSeconds` unless interactive TTY (unbounded).
    static func resolveWatchMaxWait(
        opts: Options,
        stdoutIsTTY: Bool,
        defaultNonTTYSeconds: TimeInterval = defaultNonTTYMaxWaitSeconds
    ) throws -> (seconds: TimeInterval?, applied: Bool) {
        if let raw = opts.value("max-wait") {
            return (try parseMaxWaitSeconds(raw), false)
        }
        if stdoutIsTTY { return (nil, false) }
        return (defaultNonTTYSeconds, true)
    }

    static func parseMaxWaitSeconds(_ raw: String) throws -> TimeInterval {
        guard let n = Int(raw), n > 0 else {
            throw PilotCLIError.invalidMaxWait(raw)
        }
        return TimeInterval(n)
    }

    static func stdoutIsTTY() -> Bool {
        #if canImport(Darwin)
        return isatty(STDOUT_FILENO) == 1
        #else
        return false
        #endif
    }

    static func watchStillRunning(state: RelayState, recovery: InFlightRecovery) -> Bool {
        state.status == .running && recovery == .handoffAlive
    }

    static func pilotStatusReattachCommand(relayId: String) -> String {
        "alln loop status \(relayId) --wait-for parked --timeout 7200 --json"
    }

    static func watchGoodbyeNote(relayId: String, reason: WatchEndReason, stillRunning: Bool) -> String {
        let statusCmd = pilotStatusReattachCommand(relayId: relayId)
        switch reason {
        case .interrupted:
            if stillRunning {
                return "watch ended (signal) — round still running; wait with `\(statusCmd)` (a killed watch is not a failed round)."
            }
            return "watch ended (signal) — inspect `\(statusCmd)` before any new handoff."
        case .maxWaitExpired:
            if stillRunning {
                return "watch max-wait reached — round still running; wait with `\(statusCmd)` (a killed watch is not a failed round)."
            }
            return "watch max-wait reached — inspect `\(statusCmd)` before any new handoff."
        }
    }

    /// Polls until the in-flight round settles (`status != .running`) — `.running` only
    /// ever happens transiently, while a `pilot handoff` dev turn is dispatching.
    /// When settled (or nothing was in flight), returns the same envelope as a blocking
    /// handoff: `relay` + verbatim `devReport` + optional `note`.
    static func runWatch(
        _ args: [String],
        stateStore: RelayStateStore = RelayStateStore(),
        threadProjector: RelayThreadProjector? = RelayThreadProjector(),
        runStore: RunStore = RunStore(),
        pollInterval: TimeInterval = 1.0,
        heartbeatInterval: TimeInterval = watchHeartbeatSeconds,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        now: () -> Date = Date.init,
        stdoutIsTTY: () -> Bool = stdoutIsTTY,
        interruptFlag: WatchInterruptFlag = WatchInterruptFlag(),
        installInterruptHandlers: (WatchInterruptFlag) -> [DispatchSourceSignal] = installWatchInterruptHandlers
    ) {
        guard !args.isEmpty else { usage("pilot watch --relay <id> [--max-wait <seconds>] [--json]") }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        let maxWait: (seconds: TimeInterval?, applied: Bool)
        do {
            maxWait = try resolveWatchMaxWait(opts: opts, stdoutIsTTY: stdoutIsTTY())
        } catch let error as PilotCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        guard var loaded = loadRelayState(
            relayId: relayId, stateStore: stateStore, threadProjector: threadProjector, reconcileOrphans: false
        ) else { fail(.relayNotFound(relayId)) }

        let json = opts.flag("json")
        let note: String?
        if loaded.state.status != .running {
            note = watchSettledNote(recovery: loaded.recovery, status: loaded.state.status)
        } else {
            note = nil
            let signalSources = installInterruptHandlers(interruptFlag)
            defer { signalSources.forEach { $0.cancel() } }
            let startedAt = now()
            var lastHeartbeat = startedAt
            while loaded.state.status == .running {
                if interruptFlag.isInterrupted {
                    finishWatchEarly(
                        relayId: relayId, reason: .interrupted, maxWaitApplied: maxWait.applied,
                        stateStore: stateStore, threadProjector: threadProjector,
                        runStore: runStore, json: json
                    )
                }
                let elapsed = now().timeIntervalSince(startedAt)
                if let cap = maxWait.seconds, elapsed >= cap {
                    finishWatchEarly(
                        relayId: relayId, reason: .maxWaitExpired, maxWaitApplied: maxWait.applied,
                        stateStore: stateStore, threadProjector: threadProjector,
                        runStore: runStore, json: json
                    )
                }
                if now().timeIntervalSince(lastHeartbeat) >= heartbeatInterval {
                    lastHeartbeat = now()
                    emitWatchHeartbeat(elapsedSeconds: Int(elapsed), json: json)
                }
                sleep(pollInterval)
                guard let reloaded = loadRelayState(
                    relayId: relayId, stateStore: stateStore, threadProjector: threadProjector, reconcileOrphans: true
                ) else { fail(.relayNotFound(relayId)) }
                loaded = reloaded
            }
        }
        refreshPilotProjectGit(relayId: relayId, stateStore: stateStore)
        emitWatchResult(
            loaded.state, note: note, json: json, runStore: runStore,
            maxWaitApplied: maxWait.applied ? true : nil
        )
    }

    /// SIGTERM/SIGINT or max-wait: load once without orphan reconcile, emit goodbye, exit 0.
    private static func finishWatchEarly(
        relayId: String,
        reason: WatchEndReason,
        maxWaitApplied: Bool,
        stateStore: RelayStateStore,
        threadProjector: RelayThreadProjector?,
        runStore: RunStore,
        json: Bool
    ) -> Never {
        guard let loaded = loadRelayState(
            relayId: relayId, stateStore: stateStore, threadProjector: threadProjector, reconcileOrphans: false
        ) else { fail(.relayNotFound(relayId)) }
        let stillRunning = watchStillRunning(state: loaded.state, recovery: loaded.recovery)
        let note = watchGoodbyeNote(relayId: relayId, reason: reason, stillRunning: stillRunning)
        emitWatchResult(
            loaded.state, note: note, json: json, runStore: runStore,
            stillRunning: stillRunning, maxWaitApplied: maxWaitApplied ? true : nil,
            exitOnTerminalFailure: false
        )
        exit(0)
    }

    private static func installWatchInterruptHandlers(on flag: WatchInterruptFlag) -> [DispatchSourceSignal] {
        [SIGTERM, SIGINT].map { sig in
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler {
                source.cancel()
                flag.fire()
            }
            signal(sig, SIG_IGN)
            source.resume()
            return source
        }
    }

    private static func emitWatchHeartbeat(elapsedSeconds: Int, json: Bool) {
        if json {
            print(AllnighterCLI.jsonLine(PilotWatchHeartbeatJSON(
                elapsedSeconds: elapsedSeconds, status: RelayState.Status.running.rawValue
            )))
        } else {
            print("[pilot watch] \(elapsedSeconds)s elapsed — status=running")
        }
    }

    // MARK: - adopt (reverse flip: spawned → pilot)

    /// `alln pair pilot adopt --relay <id>` (docs/phases/Pilot_Relay.md §5 "falls out
    /// of the same move") — hands a PARKED SPAWNED relay's PM seat to a piloting
    /// session. Genuinely trivial: `RelayCoordinator.adoptToPilot` is a static state
    /// flip, no dispatch, so this needs no `ToolRuntime`/`RunService` at all — the
    /// only CLI verb in this file that doesn't.
    static func runAdopt(
        _ args: [String],
        stateStore: RelayStateStore = RelayStateStore(),
        threadProjector: RelayThreadProjector? = RelayThreadProjector()
    ) {
        guard !args.isEmpty else { usage("pilot adopt --relay <id> [--json]") }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        let result = RelayCoordinator.adoptToPilot(relayId: relayId, stateStore: stateStore, threadProjector: threadProjector)
        switch result {
        case .success(let state):
            emitState(state, json: opts.flag("json"))
        case .failure(let error):
            failReverseAdopt(error)
        }
    }

    // MARK: - Output

    static func handoffNextCommand(relayId: String, scaffoldPath: String) -> String {
        "alln loop step \(relayId) \"<order for the dev>\" (or --done <summary> to close the loop) — draft it from \(shellQuote(scaffoldPath))"
    }

    /// POSIX single-quote so the printed `next:` command survives copy-paste as ONE argument.
    /// The default scaffold path lives under "…/Application Support/Allnighter/…" — the space
    /// split the unquoted command and the first handoff failed on every default install.
    /// (SR-13 / Sol F20.) JSON consumers should use `scaffoldPath` / `nextCommandArgv`, not this.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func emitStartResult(
        _ state: RelayState,
        devModelId: String,
        devWorkerAlias: String?,
        rememberedDevWorker: Bool,
        scaffoldPath: String,
        json: Bool
    ) {
        let relayJSON = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        let nextCommand = handoffNextCommand(relayId: state.id, scaffoldPath: scaffoldPath)
        let nextArgv = PilotStartJSON.defaultHandoffArgv(relayId: state.id, scaffoldPath: scaffoldPath)
        if json {
            print(AllnighterCLI.jsonString(PilotStartJSON(
                relay: relayJSON,
                nextCommand: nextCommand,
                scaffoldPath: scaffoldPath,
                nextCommandArgv: nextArgv,
                devModelId: devModelId,
                rememberedDevWorker: rememberedDevWorker ? true : nil
            )))
        } else {
            print(RelayDispatch.humanRelaySummary(relayJSON))
            if let alias = devWorkerAlias {
                print("dev seat: \(devModelId) (resolved from alias \"\(alias)\")")
            } else if rememberedDevWorker {
                print("dev seat: \(devModelId) (remembered from last pilot start on this project)")
            } else {
                print("dev seat: \(devModelId)")
            }
            print("scaffold: \(scaffoldPath)")
            print("next: \(nextCommand)")
        }
    }

    private static func emitState(_ state: RelayState, json: Bool) {
        let relayJSON = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        if json {
            print(AllnighterCLI.jsonString(relayJSON))
        } else {
            print(RelayDispatch.humanRelaySummary(relayJSON))
            let log = RelayDispatch.humanRoundLog(relayJSON)
            if !log.isEmpty { print(log) }
            print(nextActionLine(for: state))
        }
    }

    // `emitStatusResult` (the print/JSON orchestration for the now-deleted raw-args
    // `pilot status`) is gone with its only caller. `makeStatusJSON` below is not —
    // it's the `PilotStatusJSON` builder, exercised directly by
    // `PilotCLITests`/`OURLiveStatusUsageTests`/`CompletionDeliveryWorksTests`/
    // `PilotRelayStatusParityTests` independent of any CLI entry point.

    /// Product-owned agent poll cadence while a Pilot round is `.running` (PLT-S02).
    static let statusWaitHintSeconds: Double = 45
    /// PLS-S02: warn agents when stream silence exceeds this multiple of `waitHintSeconds`.
    static let streamSilenceWarningMultiplier: Double = 6

    /// Builds `pilot status --json` — long-job fields only while `.running` + handoff alive.
    /// CD-S01a: always attaches shared `devLeg` (running / settling / parked).
    static func makeStatusJSON(
        state: RelayState,
        recovery: InFlightRecovery,
        stateStore: RelayStateStore,
        runStore: RunStore = RunStore(),
        pmTurnStore: PMTurnStore? = nil,
        gitObserver: GitObserver = GitObserver(),
        now: Date = Date()
    ) -> PilotStatusJSON {
        let longJob = longJobStatusFields(
            state: state, recovery: recovery, stateStore: stateStore,
            runStore: runStore, gitObserver: gitObserver, now: now
        )
        let devLeg = StreamLiveness.devLegProjection(state: state, runStore: runStore)
        // OUR-S02: observed usage for active linked dev seat (nil when no devRunId).
        let liveUsage = ObservedUsagePresentation.liveDevUsage(
            state: state, runStore: runStore
        )
        let usagePresentation = liveUsage?.presentation
        let heroLine: String? = {
            guard state.status == .running,
                  longJob.elapsedSeconds != nil || liveUsage != nil else { return nil }
            return ObservedUsagePresentation.liveHeroLine(
                ownerAlive: longJob.ownerAlive,
                silenceAgeSeconds: longJob.silenceAgeSeconds,
                elapsedSeconds: longJob.elapsedSeconds,
                usagePresentation: usagePresentation
            )
        }()
        let pmTurn = PMTurnStatusProjection.load(
            kind: .relay,
            subjectId: state.id,
            atPMBoundary: PMTurnStatusProjection.isRelayPMBoundary(state.status),
            store: pmTurnStore ?? PMTurnStore(relaysRootDirectory: stateStore.rootDirectory)
        )
        return PilotStatusJSON(
            relay: RelayJSON.project(
                state,
                contractVersion: ContractRegistry.contractVersion,
                pmTurn: pmTurn.pmTurn,
                notes: pmTurn.notes,
                pmTurnDelivery: pmTurn.pmTurnDelivery,
                runStore: runStore
            ),
            pmTurn: pmTurn.pmTurn,
            notes: pmTurn.notes,
            pmTurnDelivery: pmTurn.pmTurnDelivery,
            recovery: recoveryActionLine(
                for: state, recovery: recovery,
                streamSilenceWarning: longJob.streamSilenceWarning,
                devLeg: devLeg
            ),
            nextActions: statusNextActions(
                for: state, recovery: recovery,
                streamSilenceWarning: longJob.streamSilenceWarning,
                devLeg: devLeg
            ),
            elapsedSeconds: longJob.elapsedSeconds,
            ownerAlive: longJob.ownerAlive,
            lastProgressAt: longJob.lastProgressAt,
            silenceAgeSeconds: longJob.silenceAgeSeconds,
            streamSilenceWarning: longJob.streamSilenceWarning,
            commitsSinceBaseline: longJob.commitsSinceBaseline,
            waitHintSeconds: longJob.waitHintSeconds,
            watcherDisposable: longJob.watcherDisposable,
            devLeg: devLeg,
            observedUsage: liveUsage,
            usagePresentation: usagePresentation,
            liveLine: heroLine
        )
    }

    /// Stream-primary long-job fields (PLT-S02 + PLS-S01 + OUR-S02).
    /// Emit while `.running` with a live handoff **or** a linked `devRunId`
    /// (dead-owner / silent-stream still need hero duration + usage segments).
    static func longJobStatusFields(
        state: RelayState,
        recovery: InFlightRecovery,
        stateStore: RelayStateStore,
        runStore: RunStore = RunStore(),
        gitObserver: GitObserver = GitObserver(),
        now: Date = Date()
    ) -> (
        elapsedSeconds: Int?,
        ownerAlive: Bool?,
        lastProgressAt: Date?,
        silenceAgeSeconds: Int?,
        streamSilenceWarning: Bool?,
        commitsSinceBaseline: Int?,
        waitHintSeconds: Double?,
        watcherDisposable: Bool?
    ) {
        let hasDevLeg = state.rounds.last?.devRunId != nil
        guard state.status == .running, recovery == .handoffAlive || hasDevLeg else {
            return (nil, nil, nil, nil, nil, nil, nil, nil)
        }
        let startedAt = state.rounds.last?.startedAt
        let elapsed = startedAt.map { max(0, Int(now.timeIntervalSince($0))) }
        let lastProgress = resolveLastProgressAt(state: state, runStore: runStore)
        let silence = lastProgress.map { max(0, Int(now.timeIntervalSince($0))) }
        let warnThreshold = Int(StreamLiveness.waitHintSeconds * StreamLiveness.warningMultiplier)
        let streamWarning = silence.map { $0 > warnThreshold } ?? false
        let commits = commitsSinceBaseline(state: state, gitObserver: gitObserver)
        let alive = recovery == .handoffAlive
        return (
            elapsedSeconds: elapsed,
            ownerAlive: alive,
            lastProgressAt: lastProgress,
            silenceAgeSeconds: silence,
            streamSilenceWarning: streamWarning,
            commitsSinceBaseline: commits,
            waitHintSeconds: alive ? statusWaitHintSeconds : nil,
            watcherDisposable: alive
        )
    }

    /// PRIMARY liveness: worker stream activity on the in-flight dev run journal only
    /// (RLR-L6 `lastActivityAt`). Never merges relay-dir heartbeat / `pgid_activity`
    /// (PLS-S01) — those clocks are for the stall watchdog, not agent-facing status.
    static func resolveLastProgressAt(
        state: RelayState,
        runStore: RunStore
    ) -> Date? {
        StreamLiveness.relayStreamLastActivityAt(state: state, runStore: runStore)
    }

    /// SUPPLEMENTARY only — not liveness. Nil when no baseline/HEAD to observe.
    static func commitsSinceBaseline(
        state: RelayState,
        gitObserver: GitObserver = GitObserver()
    ) -> Int? {
        guard let baseline = state.rounds.last?.baselineHead,
              let head = gitObserver.observe(rootPath: state.projectRoot).head else {
            return nil
        }
        if baseline == head { return 0 }
        return gitObserver.commitsInRange(
            rootPath: state.projectRoot, baseline: baseline, head: head
        ).count
    }

    private static func emitWatchResult(
        _ state: RelayState, note: String?, json: Bool, runStore: RunStore,
        stillRunning: Bool? = nil, maxWaitApplied: Bool? = nil,
        exitOnTerminalFailure: Bool = true
    ) {
        let relayJSON = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        let devReport = stillRunning == true ? nil : RelayCoordinator.settledDevReport(for: state, runStore: runStore)
        if json {
            print(AllnighterCLI.jsonLine(PilotWatchJSON(
                relay: relayJSON, devReport: devReport, note: note,
                stillRunning: stillRunning, maxWaitApplied: maxWaitApplied
            )))
        } else {
            print(RelayDispatch.humanRelaySummary(relayJSON))
            if let note { print(note) }
            if let devReport {
                print("\n----- dev report (round \(relayJSON.rounds)) -----\n\(devReport)")
            }
            let log = RelayDispatch.humanRoundLog(relayJSON)
            if !log.isEmpty { print("\n" + log) }
            if stillRunning == true {
                print("\nreattach: \(pilotStatusReattachCommand(relayId: state.id))")
            } else {
                print("\n" + nextActionLine(for: state))
            }
        }
        if exitOnTerminalFailure, state.status == .escalated || state.status == .stopped { exit(1) }
    }

    /// Re-observe git metadata for the relay's project — pilot paths must never serve
    /// stale branch/head/dirty from the project cache (`Pilot_DX.md` §DX5).
    private static func refreshPilotProjectGit(relayId: String, stateStore: RelayStateStore) {
        guard let root = stateStore.load(id: relayId)?.projectRoot else { return }
        _ = ProjectStore().resolveFresh(root)
    }

    static func watchSettledNote(recovery: InFlightRecovery, status: RelayState.Status) -> String {
        switch recovery {
        case .handoffAlive:
            return "note: no round was in flight — relay is \(status.rawValue)."
        case .orphanReconciled:
            return "note: handoff owner died mid-round — relay reconciled to \(status.rawValue)."
        case .none:
            return "note: no round in flight — relay is \(status.rawValue)."
        }
    }

    static func recoveryActionLine(
        for state: RelayState,
        recovery: InFlightRecovery,
        streamSilenceWarning: Bool? = nil,
        devLeg: RelayDevLegProjection? = nil
    ) -> String? {
        switch recovery {
        case .none:
            return nil
        case .handoffAlive:
            if devLeg?.phase == .settling {
                var line = "dev leg terminal (settling) — worker finished; harness settlement still in progress. Wait with `alln loop status \(state.id) --wait-for parked --timeout 7200 --json`. Relay running ≠ dev running — check devRunId\(devLeg?.devRunId.map { " (\($0))" } ?? "")."
                if let end = devLeg?.devEndReason {
                    line += " devEndReason=\(end)."
                }
                return line
            }
            var line = "in flight — handoff process alive; wait with `alln loop status \(state.id) --wait-for parked --timeout 7200 --json` until it settles (stream silence is primary liveness — matches `alln ps`; commitsSinceBaseline is supplementary only). Optional: `alln loop wait \(state.id)`. A killed watch is not a failed round."
            if streamSilenceWarning == true {
                line += " streamSilenceWarning: worker stream has been silent longer than \(Int(statusWaitHintSeconds * streamSilenceWarningMultiplier))s — inspect with `alln ps` (process tree may still be busy without worker output)."
            }
            return line
        case .orphanReconciled:
            return "handoff owner died mid-round — relay reconciled (\(state.stoppedReason ?? RelayState.orphanReconciledReason)); inspect `alln loop status \(state.id) --json` and the repo before any new handoff — do not blind retry."
        }
    }

    static func recoveryNextActions(
        for state: RelayState,
        recovery: InFlightRecovery,
        streamSilenceWarning: Bool? = nil
    ) -> [AgentSurfaceNextAction] {
        switch recovery {
        case .none:
            return []
        case .handoffAlive:
            var actions: [AgentSurfaceNextAction] = [
                .init(
                    kind: "pilotStatus",
                    label: "Wait for the parked PM Turn (stream silence primary; commits supplementary)",
                    command: "alln loop status \(state.id) --wait-for parked --timeout 7200 --json"
                ),
                .init(
                    kind: "pilotWatch",
                    label: "Optional: block interactively until the round settles (disposable waiter)",
                    command: "alln loop wait \(state.id) --json"
                ),
            ]
            if streamSilenceWarning == true {
                actions.insert(.init(
                    kind: "inspectStreamSilence",
                    label: "Stream silence warning — correlate with `alln ps` before assuming the dev seat is progressing",
                    command: "alln ps --json"
                ), at: 0)
            }
            return actions
        case .orphanReconciled:
            return [.init(
                kind: "pilotStatus",
                label: "Inspect reconciled relay state before any new handoff",
                command: "alln loop status \(state.id) --json"
            )]
        }
    }

    /// CD-S01a: prefer settling / parked next-actions over "wait as if dev still live".
    static func statusNextActions(
        for state: RelayState,
        recovery: InFlightRecovery,
        streamSilenceWarning: Bool? = nil,
        devLeg: RelayDevLegProjection
    ) -> [AgentSurfaceNextAction] {
        switch devLeg.phase {
        case .settling:
            var actions: [AgentSurfaceNextAction] = [
                .init(
                    kind: "waitForSettlement",
                    label: "Dev leg terminal — wait for relay to park (not progress on a dead dev)",
                    command: "alln loop status \(state.id) --wait-for parked --timeout 7200 --json"
                ),
            ]
            if let devRunId = devLeg.devRunId {
                actions.append(.init(
                    kind: "inspectDevRun",
                    label: "Inspect terminal dev run facts",
                    command: "alln team status \(devRunId) --json"
                ))
            }
            return actions
        case .parked:
            if state.status == .awaitingPM, state.isCallerChair {
                return [
                    .init(
                        kind: "pilotHandoff",
                        label: "Review pmTurn.report (dev report), then hand off the next order",
                        command: "alln loop step \(state.id) \"<order for the dev>\" --json"
                    ),
                    .init(
                        kind: "inspectDevRun",
                        label: "Inspect terminal dev run facts",
                        command: devLeg.devRunId.map { "alln team status \($0) --json" }
                            ?? "alln loop status \(state.id) --json"
                    ),
                ]
            }
            return recoveryNextActions(
                for: state, recovery: recovery, streamSilenceWarning: streamSilenceWarning
            )
        case .running, .none:
            return recoveryNextActions(
                for: state, recovery: recovery, streamSilenceWarning: streamSilenceWarning
            )
        }
    }

    static func humanDevLegLine(_ devLeg: RelayDevLegProjection) -> String? {
        switch devLeg.phase {
        case .none:
            return nil
        case .running:
            guard let id = devLeg.devRunId else { return nil }
            return "dev leg: running · \(id)\(devLeg.devRunStatus.map { " · \($0)" } ?? "")"
        case .settling:
            var parts = ["dev leg: settling (worker terminal — not aggregate progress)"]
            if let id = devLeg.devRunId { parts.append(id) }
            if let st = devLeg.devRunStatus { parts.append(st) }
            if let end = devLeg.devEndReason { parts.append("endReason=\(end)") }
            if let commit = devLeg.commit { parts.append("commit=\(commit)") }
            return parts.joined(separator: " · ")
        case .parked:
            var parts = ["dev leg: parked"]
            if let id = devLeg.devRunId { parts.append(id) }
            if let st = devLeg.devRunStatus { parts.append(st) }
            if let end = devLeg.devEndReason { parts.append("endReason=\(end)") }
            if let commit = devLeg.commit { parts.append("commit=\(commit)") }
            return parts.joined(separator: " · ")
        }
    }

    /// The next-action discipline (Pilot_Relay.md §1 decision 5): every non-JSON print
    /// says, in one line, what the piloting session should do next.
    static func nextActionLine(for state: RelayState, devLeg: RelayDevLegProjection? = nil) -> String {
        if devLeg?.phase == .settling {
            return "dev leg terminal (settling) — wait with `alln loop status \(state.id) --wait-for parked --timeout 7200 --json`; do not treat relay running as proof the dev worker is still live (check devRunId)."
        }
        switch state.status {
        case .awaitingPM:
            return "next: write this round's order, then `alln loop step \(state.id) \"<order for the dev>\"` (or `--done <summary>` to close the loop)."
        case .running:
            return "a round is in flight — wait with `alln loop status \(state.id) --wait-for parked --timeout 7200 --json`; do not re-dispatch while running (optional: `alln loop wait \(state.id)`)."
        case .done:
            return "relay done — nothing left to hand off."
        case .escalated:
            return "relay escalated — parked; \(state.note ?? "a founder question is open"). No further `loop step` calls are accepted until this is resolved."
        case .stopped:
            return "relay stopped (\(state.stoppedReason ?? "a ceiling was reached")) — no further `loop step` calls are accepted."
        }
    }

    // MARK: - Errors

    enum PilotCLIError: Error, Equatable {
        case missingRequired(String)
        case invalidMaxRounds(String)
        case invalidIdleTimeout(String)
        case projectNotFound(String)
        case relayNotFound(String)
        case noSubmission
        case noHandover
        case fileUnreadable(String)
        case invalidVerdict(String)
        case mutuallyExclusive(String, String)
        case ambiguousDevWorker(alias: String, candidates: String)
        case devWorkerNotFound(alias: String, readySeats: String)
        case missingDevWorker(readySeats: String)
        case noReadyDevSeats
        case invalidMaxWait(String)
    }

    static func errorEnvelope(_ error: PilotCLIError) -> (code: String, message: String) {
        switch error {
        case .missingRequired(let flag):
            return ("CLI_USAGE_ERROR", "\(flag) required")
        case .invalidMaxRounds(let raw):
            return ("CLI_USAGE_ERROR", "--max-rounds must be a positive integer, got '\(raw)'")
        case .invalidIdleTimeout(let message):
            return ("CLI_USAGE_ERROR", message)
        case .projectNotFound(let token):
            return ("PROJECT_NOT_FOUND", "project not found: \(token)")
        case .relayNotFound(let id):
            return ("RELAY_NOT_FOUND", "relay not found: \(id)")
        case .noSubmission:
            return ("CLI_USAGE_ERROR", "no submission text — pass --file <md> or pipe markdown via stdin")
        case .noHandover:
            return ("CLI_USAGE_ERROR", "no handover text — pass --handover-file <path> or --handover-stdin")
        case .fileUnreadable(let path):
            return ("CLI_USAGE_ERROR", "could not read submission file: \(path)")
        case .invalidVerdict(let raw):
            return ("CLI_USAGE_ERROR", "--verdict must be continue, done, or escalate — got '\(raw)'")
        case .mutuallyExclusive(let a, let b):
            return ("CLI_USAGE_ERROR", "\(a) cannot be combined with \(b)")
        case .ambiguousDevWorker(let alias, let candidates):
            return ("CLI_USAGE_ERROR", "ambiguous dev seat alias \"\(alias)\" — matches: \(candidates)")
        case .devWorkerNotFound(let alias, let readySeats):
            return ("CLI_USAGE_ERROR", "no dev seat matches \"\(alias)\" — ready seats: \(readySeats)")
        case .missingDevWorker(let readySeats):
            return ("CLI_USAGE_ERROR", "--dev <seat|alias> required (no remembered seat for this project) — ready seats: \(readySeats)")
        case .noReadyDevSeats:
            return ("CLI_USAGE_ERROR", "no ready dev seats — run `alln doctor --full`")
        case .invalidMaxWait(let raw):
            return ("CLI_USAGE_ERROR", "--max-wait must be a positive integer, got '\(raw)'")
        }
    }

    static func pilotRoundErrorEnvelope(_ error: RelayCoordinator.PilotRoundError) -> (code: String, message: String) {
        switch error {
        case .relayNotFound:
            return ("RELAY_NOT_FOUND", "relay not found")
        case .notPilotRelay:
            return ("RELAY_INVALID_STATE", "relay is not a Pilot relay (caller doesn't hold the PM seat) — check it with `alln loop status <loop-id>`, or take the chair with `alln loop pm <loop-id> caller`")
        case .roundInFlight:
            return ("RELAY_ROUND_IN_FLIGHT", "a round is already dispatching for this relay — wait with `alln loop status <loop-id> --wait-for parked --timeout 7200 --json`; do not re-dispatch while running (optional: `alln loop wait <loop-id>`)")
        case .notAwaitingPM(let status):
            return ("RELAY_NOT_AWAITING_PM", "relay is \(status), not awaitingPM — nothing to hand off to")
        case .verdictUnparseable(let parseError):
            return ("RELAY_VERDICT_UNPARSEABLE", describeParseError(parseError))
        case .handoverBlocked(let dangerClass, let code, let reason, let snippet):
            return ("RELAY_HANDOVER_UNSAFE", "HandoverGate blocked (\(dangerClass), \(code)): \(reason) — \"\(snippet)\". The relay stays awaitingPM — rephrase the handover and resubmit.")
        }
    }

    static func reverseAdoptErrorEnvelope(_ error: RelayCoordinator.ReverseAdoptError) -> (code: String, message: String) {
        switch error {
        case .relayNotFound:
            return ("RELAY_NOT_FOUND", "relay not found")
        case .notSpawnedRelay:
            return ("RELAY_INVALID_STATE", "relay is not a spawned relay (caller already holds the PM seat) — only a spawned relay can be handed to a piloting session")
        case .notAdoptable(let status):
            return ("RELAY_INVALID_STATE", "relay is \(status), not adoptable — only an escalated or ceiling-stopped (and reconciled) spawned relay can be handed to Pilot")
        }
    }

    private static func describeParseError(_ error: RelayVerdictParser.ExtractError) -> String {
        switch error {
        case .noVerdictFound:
            return "no JSON object anywhere in the submission carried a `verdict` key — the tail was missing entirely."
        case .unknownVerdict(let raw):
            return "the `verdict` value \"\(raw)\" isn't one of `continue`, `done`, `escalate`."
        case .continueWithoutHandover:
            return "`verdict: \"continue\"` was sent but `handover` was missing or empty — it's required whenever the relay continues."
        }
    }

    private static func fail(_ error: PilotCLIError) -> Never {
        let (code, message) = errorEnvelope(error)
        AllnighterCLI.fail(code: code, message: message)
    }

    /// Not `private` — shared with `LoopCLI.runStep` (LVC-S02d).
    static func failPilotRound(_ error: RelayCoordinator.PilotRoundError) -> Never {
        let (code, message) = pilotRoundErrorEnvelope(error)
        AllnighterCLI.fail(code: code, message: message)
    }

    private static func failReverseAdopt(_ error: RelayCoordinator.ReverseAdoptError) -> Never {
        let (code, message) = reverseAdoptErrorEnvelope(error)
        AllnighterCLI.fail(code: code, message: message)
    }

    private static func usage(_ detail: String = "pilot start|handoff|status|watch|adopt|scaffold-handover") -> Never {
        FileHandle.standardError.write(Data("usage: alln pair \(detail)\n".utf8))
        exit(2)
    }
}

/// Single-line JSON ack on `pilot handoff --no-wait --json` before the detached child runs.
struct PilotHandoffDispatchJSON: Encodable {
    let relayId: String
    let status: String
    let roundInFlight: Bool
    let pid: Int32
    /// URN-S02: outcome of the `alln serve` auto-launch guarantee for this
    /// dispatch — `"alreadyRunning" | "launched" | "skipped" | "failed"`.
    let serveAutoLaunch: String
    let delivery: DetachedDispatchJSON.Delivery
}

/// `pilot handoff --json` envelope: the same `RelayJSON` every other relay verb emits,
/// plus the dev's report verbatim when a dev turn delivered in THIS call (nil for a
/// done/escalate/ceiling/stagnation round, or when the dev turn never delivered).
struct PilotHandoffJSON: Encodable {
    let relay: RelayJSON
    let devReport: String?
}

/// `pilot status --json` envelope: relay state plus typed recovery when `.running`.
/// Long-job fields (PLT-S02) are present while `.running` with a live handoff owner;
/// omitted otherwise. `lastProgressAt`/`silenceAgeSeconds` are PRIMARY stream liveness
/// (RLR-L6 `lastActivityAt` on the linked dev run — same truth as `alln ps`);
/// `streamSilenceWarning` when silence exceeds 6×`waitHintSeconds`; `commitsSinceBaseline`
/// is SUPPLEMENTARY only (not proof of life).
/// CD-S01a: `devLeg` is always present (shared with `relay-status`).
struct PilotStatusJSON: Encodable {
    var relay: RelayJSON
    let pmTurn: PMTurnJSON?
    let notes: [String]
    let pmTurnDelivery: PMTurnDeliveryJSON?
    let recovery: String?
    let nextActions: [AgentSurfaceNextAction]
    let elapsedSeconds: Int?
    let ownerAlive: Bool?
    let lastProgressAt: Date?
    let silenceAgeSeconds: Int?
    let streamSilenceWarning: Bool?
    let commitsSinceBaseline: Int?
    let waitHintSeconds: Double?
    let watcherDisposable: Bool?
    var waitOutcome: String?
    let devLeg: RelayDevLegProjection?
    /// OUR-S02: structured observed usage for the active linked dev seat.
    let observedUsage: LiveUsageProjection?
    /// OUR-S02: compact tok or blame string (human + JSON parity).
    let usagePresentation: String?
    /// OUR-S02: full hero line (`alive · stream … · duration · tok/blame`).
    let liveLine: String?

    init(
        relay: RelayJSON,
        pmTurn: PMTurnJSON? = nil,
        notes: [String] = [],
        pmTurnDelivery: PMTurnDeliveryJSON? = nil,
        recovery: String?,
        nextActions: [AgentSurfaceNextAction],
        elapsedSeconds: Int? = nil,
        ownerAlive: Bool? = nil,
        lastProgressAt: Date? = nil,
        silenceAgeSeconds: Int? = nil,
        streamSilenceWarning: Bool? = nil,
        commitsSinceBaseline: Int? = nil,
        waitHintSeconds: Double? = nil,
        watcherDisposable: Bool? = nil,
        waitOutcome: String? = nil,
        devLeg: RelayDevLegProjection? = nil,
        observedUsage: LiveUsageProjection? = nil,
        usagePresentation: String? = nil,
        liveLine: String? = nil
    ) {
        self.relay = relay
        self.pmTurn = pmTurn
        self.notes = notes
        self.pmTurnDelivery = pmTurnDelivery
        self.recovery = recovery
        self.nextActions = nextActions
        self.elapsedSeconds = elapsedSeconds
        self.ownerAlive = ownerAlive
        self.lastProgressAt = lastProgressAt
        self.silenceAgeSeconds = silenceAgeSeconds
        self.streamSilenceWarning = streamSilenceWarning
        self.commitsSinceBaseline = commitsSinceBaseline
        self.waitHintSeconds = waitHintSeconds
        self.watcherDisposable = watcherDisposable
        self.waitOutcome = waitOutcome
        self.devLeg = devLeg
        self.observedUsage = observedUsage
        self.usagePresentation = usagePresentation
        self.liveLine = liveLine
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(relay, forKey: .relay)
        try c.encode(pmTurn, forKey: .pmTurn)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(pmTurnDelivery, forKey: .pmTurnDelivery)
        try c.encodeIfPresent(recovery, forKey: .recovery)
        try c.encode(nextActions, forKey: .nextActions)
        try c.encodeIfPresent(elapsedSeconds, forKey: .elapsedSeconds)
        try c.encodeIfPresent(ownerAlive, forKey: .ownerAlive)
        try c.encodeIfPresent(lastProgressAt, forKey: .lastProgressAt)
        try c.encodeIfPresent(silenceAgeSeconds, forKey: .silenceAgeSeconds)
        try c.encodeIfPresent(streamSilenceWarning, forKey: .streamSilenceWarning)
        try c.encodeIfPresent(commitsSinceBaseline, forKey: .commitsSinceBaseline)
        try c.encodeIfPresent(waitHintSeconds, forKey: .waitHintSeconds)
        try c.encodeIfPresent(watcherDisposable, forKey: .watcherDisposable)
        try c.encodeIfPresent(waitOutcome, forKey: .waitOutcome)
        try c.encodeIfPresent(devLeg, forKey: .devLeg)
        try c.encodeIfPresent(observedUsage, forKey: .observedUsage)
        try c.encodeIfPresent(usagePresentation, forKey: .usagePresentation)
        try c.encodeIfPresent(liveLine, forKey: .liveLine)
    }

    private enum CodingKeys: String, CodingKey {
        case relay, pmTurn, notes, pmTurnDelivery, recovery, nextActions
        case elapsedSeconds, ownerAlive, lastProgressAt, silenceAgeSeconds
        case streamSilenceWarning, commitsSinceBaseline, waitHintSeconds, watcherDisposable
        case waitOutcome, devLeg, observedUsage, usagePresentation, liveLine
    }
}

/// `pilot watch --json` envelope: same as a blocking handoff when settled, plus an
/// optional note when nothing was in flight. On signal/max-wait while still running,
/// carries `stillRunning` + reattach guidance instead of looking like round failure.
struct PilotWatchJSON: Encodable {
    let relay: RelayJSON
    let devReport: String?
    let note: String?
    let stillRunning: Bool?
    let maxWaitApplied: Bool?

    init(
        relay: RelayJSON, devReport: String?, note: String?,
        stillRunning: Bool? = nil, maxWaitApplied: Bool? = nil
    ) {
        self.relay = relay
        self.devReport = devReport
        self.note = note
        self.stillRunning = stillRunning
        self.maxWaitApplied = maxWaitApplied
    }
}

/// NDJSON heartbeat line while `pilot watch` is waiting on a `.running` round.
struct PilotWatchHeartbeatJSON: Encodable {
    let kind: String
    let elapsedSeconds: Int
    let status: String

    init(elapsedSeconds: Int, status: String) {
        kind = "pilotWatchHeartbeat"
        self.elapsedSeconds = elapsedSeconds
        self.status = status
    }
}
