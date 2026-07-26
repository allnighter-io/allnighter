import Foundation
import AllnighterCore
import AllnighterEngine
#if canImport(Darwin)
import Darwin
#endif

/// `alln pair pilot start|handoff|status|watch` — Pilot (`docs/phases/Pilot_Relay.md`):
/// this session is the PM, Allnighter runs the crew (dev seat + rails). Same substrate
/// as `pair relay`/`RelayCLI` — `RelayCoordinator.startPilot`/`runExternalRound` do all
/// the work; this file is a thin CLI projection, mirroring `RelayCLI`'s shape (throwing,
/// store-injectable, exit-free `parse*` helpers so the recovery ladder is unit-testable
/// without a subprocess; only the thin `run*` entry points touch `exit()`).
///
/// CLI is the ONLY agent surface for Pilot (`docs/phases/MCP_Retirement.md` — MCP is
/// retired). A piloting session drives the loop by running `alln` directly: `pilot
/// start` once, then one blocking `pilot handoff` call per round — read the printed dev
/// report, think, call `handoff` again.
enum PilotCLI {
    /// Resolved `pilot start` inputs after flag parsing, alias resolution, and optional recall.
    struct StartRequest {
        var config: RelayCoordinator.Config
        var devWorkerId: String
        /// The raw `--dev-worker` token when it differed from the resolved model id.
        var devWorkerAlias: String?
        var rememberedDevWorker: Bool
    }

    static func run(_ args: [String], runtime: ToolRuntime) async {
        guard let sub = args.first else { usage() }
        switch sub {
        case "start": await runStart(Array(args.dropFirst()), runtime: runtime)
        case "handoff": await runHandoff(Array(args.dropFirst()), runtime: runtime)
        case "status": runStatus(Array(args.dropFirst()))
        case "watch": runWatch(Array(args.dropFirst()))
        case "adopt": runAdopt(Array(args.dropFirst()))
        case "scaffold-handover": runScaffoldHandover(Array(args.dropFirst()))
        default: usage()
        }
    }

    // MARK: - start

    static func runStart(_ args: [String], runtime: ToolRuntime) async {
        guard !args.isEmpty else { usage("pilot start --doc <path> --project <id|path> [--dev-worker <seat|alias>] [--max-rounds N] [--idle-timeout <seconds>] [--json]") }
        let opts = Options(args)
        let request: StartRequest
        do {
            request = try parseStartConfig(
                args,
                models: runtime.models,
                probeRecords: SetupStore().load().records
            )
        } catch let error as PilotCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

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
                try PilotDevSeatStore().save(projectId: request.config.projectId ?? "", devWorkerId: request.devWorkerId)
            } catch {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not remember dev seat: \(error)")
            }
            emitStartResult(
                state,
                devWorkerId: request.devWorkerId,
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
        let readySeats = PilotSeatResolver.readySeats(from: catalogModels, probeRecords: records)

        let devWorkerId: String
        let devWorkerAlias: String?
        let remembered: Bool
        if let token = opts.value("dev-worker") {
            switch PilotSeatResolver.resolve(alias: token, models: catalogModels) {
            case .success(let resolved):
                devWorkerId = resolved
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
        } else if let rememberedId = devSeatStore.load(projectId: project.id)?.devWorkerId {
            devWorkerId = rememberedId
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
            pmWorkerId: RelayState.externalPMWorkerId,
            devWorkerId: devWorkerId,
            maxRounds: maxRounds,
            devTurnIdleTimeoutSeconds: idleParsed.value
        )
        return StartRequest(
            config: config,
            devWorkerId: devWorkerId,
            devWorkerAlias: devWorkerAlias,
            rememberedDevWorker: remembered
        )
    }

    // MARK: - scaffold-handover

    static func runScaffoldHandover(_ args: [String]) {
        guard !args.isEmpty else { usage("pilot scaffold-handover --relay <id> [--round N]") }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        let round = Int(opts.value("round") ?? "1") ?? 1
        guard round > 0 else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--round must be a positive integer")
        }
        let stateStore = RelayStateStore()
        guard stateStore.load(id: relayId) != nil else { fail(.relayNotFound(relayId)) }
        let template = PilotHandoverScaffold.template(round: round)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(["relayId": relayId, "round": String(round), "template": template]))
        } else {
            print(template, terminator: "")
        }
    }

    // MARK: - handoff

    static func runHandoff(_ args: [String], runtime: ToolRuntime) async {
        guard !args.isEmpty else {
            usage("pilot handoff --relay <id> (--file <md> | --verdict continue|done|escalate [--handover-file <path>|--handover-stdin] [--note …]) [--no-wait] [--json]")
        }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        let submission: String
        do {
            submission = try parseHandoffSubmission(opts)
        } catch let error as PilotCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        if opts.flag("no-wait") {
            dispatchHandoffInBackground(relayId: relayId, opts: opts, submission: submission, jsonRequested: opts.flag("json"))
            return
        }

        let stateStore = RelayStateStore()
        guard stateStore.load(id: relayId) != nil else { fail(.relayNotFound(relayId)) }
        let projectStore = ProjectStore()
        let projectId = projectStore.resolveFresh(
            loadedProjectRoot(relayId, stateStore: stateStore) ?? ""
        )?.id

        let emitJSON = opts.flag("json")
        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        let progressSink: RelayCoordinator.EventSink? = emitJSON ? { @Sendable event in
            print(RelayDispatch.progressJSONLine(event))
        } : nil
        let result = await coordinator.runExternalRound(
            relayId: relayId,
            submission: submission,
            projectId: projectId,
            events: progressSink
        )
        switch result {
        case .success(let payload):
            emitHandoffResult(payload, json: opts.flag("json"))
        case .failure(let error):
            failPilotRound(error)
        }
    }

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
        guard let state = stateStore.load(id: relayId) else {
            throw DetachedHandoffLaunchError.relayNotFound(relayId)
        }
        guard !state.projectRoot.isEmpty else {
            throw DetachedHandoffLaunchError.missingProjectRoot(relayId)
        }
        let executablePath: String?
        if let current = currentExecutablePath() {
            executablePath = current
        } else {
            executablePath = InstallCLI.resolvedRunningBinary(
                argv0: argv0,
                pathEnvironment: pathEnvironment
            )
        }
        guard let executablePath else {
            throw DetachedHandoffLaunchError.unresolvedExecutable
        }
        return DetachedHandoffLaunch(
            executableURL: URL(fileURLWithPath: executablePath),
            currentDirectoryURL: URL(fileURLWithPath: state.projectRoot)
        )
    }

    /// `--no-wait`: re-invokes THIS SAME executable as a detached background process
    /// running the normal (blocking) `pilot handoff` against a staged copy of the
    /// submission — one dispatch path, no second in-process implementation to drift
    /// from the default. The foreground call returns as soon as the child is launched;
    /// agents then poll `pilot status --json` (status-first); `pilot watch` is optional.
    private static func dispatchHandoffInBackground(
        relayId: String, opts: Options, submission: String, jsonRequested: Bool
    ) {
        let stateStore = RelayStateStore()
        let priorStatus = stateStore.load(id: relayId)?.status
        let roundInFlight = priorStatus == .running

        let launch: DetachedHandoffLaunch
        do {
            launch = try detachedHandoffLaunch(relayId: relayId, stateStore: stateStore)
        } catch DetachedHandoffLaunchError.relayNotFound(let id) {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "relay not found: \(id)")
        } catch DetachedHandoffLaunchError.missingProjectRoot(let id) {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "relay \(id) has no projectRoot")
        } catch DetachedHandoffLaunchError.unresolvedExecutable {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not resolve running binary for background handoff")
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not prepare background handoff: \(error)")
        }

        let process = Process()
        process.executableURL = launch.executableURL
        process.currentDirectoryURL = launch.currentDirectoryURL
        var childArgs = ["pair", "pilot", "handoff", "--relay", relayId]

        // SR-12 (Sol F19): stage the already-read/synthesized submission to an IMMUTABLE temp
        // file and hand the detached child `--file <temp>`, for every path. Previously the
        // `--handover-file` branch re-passed the caller's *live* path, so a file overwritten or
        // deleted after the foreground ack but before the child opened it made the child run
        // different or empty instructions. `submission` is already the complete markdown (prose
        // + synthesized RelayVerdict tail), so `--file` reproduces it byte-for-byte — which also
        // collapses the three divergent staging branches into one.
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-pilot-handoff-\(relayId)-\(UUID().uuidString).md")
        do {
            try submission.write(to: stagedURL, atomically: true, encoding: .utf8)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not stage handoff submission: \(error)")
        }
        childArgs += ["--file", stagedURL.path]

        if jsonRequested { childArgs.append("--json") }
        process.arguments = childArgs
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not dispatch background handoff: \(error)")
        }
        if jsonRequested {
            print(AllnighterCLI.jsonLine(PilotHandoffDispatchJSON(
                relayId: relayId, status: "dispatched", roundInFlight: roundInFlight,
                pid: process.processIdentifier)))
        } else {
            print("dispatched (pid \(process.processIdentifier)) — poll with `alln pair pilot status --relay \(relayId) --json` (optional: `alln pair pilot watch --relay \(relayId)`)")
        }
    }

    private static func emitHandoffResult(_ payload: RelayCoordinator.PilotRoundResult, json: Bool) {
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
        guard var state = stateStore.load(id: relayId) else { return nil }
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

    static func runStatus(
        _ args: [String],
        stateStore: RelayStateStore = RelayStateStore(),
        threadProjector: RelayThreadProjector? = RelayThreadProjector()
    ) {
        guard !args.isEmpty else { usage("pilot status --relay <id> [--json]") }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        guard let loaded = loadRelayState(
            relayId: relayId, stateStore: stateStore, threadProjector: threadProjector, reconcileOrphans: true
        ) else { fail(.relayNotFound(relayId)) }
        refreshPilotProjectGit(relayId: relayId, stateStore: stateStore)
        emitStatusResult(loaded.state, recovery: loaded.recovery, json: opts.flag("json"))
    }

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
            guard let seconds = try parseMaxWaitSeconds(raw) else {
                throw PilotCLIError.missingRequired("--max-wait <seconds>")
            }
            return (seconds, false)
        }
        if stdoutIsTTY { return (nil, false) }
        return (defaultNonTTYSeconds, true)
    }

    static func parseMaxWaitSeconds(_ raw: String) throws -> TimeInterval? {
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
        "alln pair pilot status --relay \(relayId) --json"
    }

    static func watchGoodbyeNote(relayId: String, reason: WatchEndReason, stillRunning: Bool) -> String {
        let statusCmd = pilotStatusReattachCommand(relayId: relayId)
        switch reason {
        case .interrupted:
            if stillRunning {
                return "watch ended (signal) — round still running; poll `\(statusCmd)` (a killed watch is not a failed round)."
            }
            return "watch ended (signal) — inspect `\(statusCmd)` before any new handoff."
        case .maxWaitExpired:
            if stillRunning {
                return "watch max-wait reached — round still running; poll `\(statusCmd)` (a killed watch is not a failed round)."
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
        "alln pair pilot handoff --relay \(relayId) --verdict continue --handover-file \(shellQuote(scaffoldPath))"
    }

    /// POSIX single-quote so the printed `next:` command survives copy-paste as ONE argument.
    /// The default scaffold path lives under "…/Application Support/Allnighter/…" — the space
    /// split the unquoted command and the first handoff failed on every default install.
    /// (SR-13 / Sol F20.)
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func emitStartResult(
        _ state: RelayState,
        devWorkerId: String,
        devWorkerAlias: String?,
        rememberedDevWorker: Bool,
        scaffoldPath: String,
        json: Bool
    ) {
        let relayJSON = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        let nextCommand = handoffNextCommand(relayId: state.id, scaffoldPath: scaffoldPath)
        if json {
            print(AllnighterCLI.jsonString(PilotStartJSON(
                relay: relayJSON,
                nextCommand: nextCommand,
                scaffoldPath: scaffoldPath,
                devWorkerId: devWorkerId,
                rememberedDevWorker: rememberedDevWorker ? true : nil
            )))
        } else {
            print(RelayDispatch.humanRelaySummary(relayJSON))
            if let alias = devWorkerAlias {
                print("dev seat: \(devWorkerId) (resolved from alias \"\(alias)\")")
            } else if rememberedDevWorker {
                print("dev seat: \(devWorkerId) (remembered from last pilot start on this project)")
            } else {
                print("dev seat: \(devWorkerId)")
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

    private static func emitStatusResult(_ state: RelayState, recovery: InFlightRecovery, json: Bool) {
        let relayJSON = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        let recoveryLine = recoveryActionLine(for: state, recovery: recovery)
        if json {
            print(AllnighterCLI.jsonString(PilotStatusJSON(
                relay: relayJSON,
                recovery: recoveryLine,
                nextActions: recoveryNextActions(for: state, recovery: recovery)
            )))
        } else {
            print(RelayDispatch.humanRelaySummary(relayJSON))
            let log = RelayDispatch.humanRoundLog(relayJSON)
            if !log.isEmpty { print(log) }
            if let recoveryLine { print(recoveryLine) }
            print(nextActionLine(for: state))
        }
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

    static func recoveryActionLine(for state: RelayState, recovery: InFlightRecovery) -> String? {
        switch recovery {
        case .none:
            return nil
        case .handoffAlive:
            return "in flight — handoff process alive; poll `alln pair pilot status --relay \(state.id) --json` until it settles (optional: `alln pair pilot watch --relay \(state.id)`). A killed watch is not a failed round."
        case .orphanReconciled:
            return "handoff owner died mid-round — relay reconciled (\(state.stoppedReason ?? RelayState.orphanReconciledReason)); inspect `alln pair pilot status --relay \(state.id) --json` and the repo before any new handoff — do not blind retry."
        }
    }

    static func recoveryNextActions(for state: RelayState, recovery: InFlightRecovery) -> [AgentSurfaceNextAction] {
        switch recovery {
        case .none:
            return []
        case .handoffAlive:
            return [
                .init(
                    kind: "pilotStatus",
                    label: "Poll durable status until the round settles",
                    command: "alln pair pilot status --relay \(state.id) --json"
                ),
                .init(
                    kind: "pilotWatch",
                    label: "Optional: block interactively until the round settles (disposable waiter)",
                    command: "alln pair pilot watch --relay \(state.id) --json"
                ),
            ]
        case .orphanReconciled:
            return [.init(
                kind: "pilotStatus",
                label: "Inspect reconciled relay state before any new handoff",
                command: "alln pair pilot status --relay \(state.id) --json"
            )]
        }
    }

    /// The next-action discipline (Pilot_Relay.md §1 decision 5): every non-JSON print
    /// says, in one line, what the piloting session should do next.
    static func nextActionLine(for state: RelayState) -> String {
        switch state.status {
        case .awaitingPM:
            return "next: write this round's order markdown, then `alln pair pilot handoff --relay \(state.id) --verdict continue --handover-file <order.md>` (or `--file <md>` with a RelayVerdict tail for scripted PM output)."
        case .running:
            return "a round is in flight — poll `alln pair pilot status --relay \(state.id) --json` until it settles; do not re-dispatch while running (optional: `alln pair pilot watch --relay \(state.id)`)."
        case .done:
            return "relay done — nothing left to hand off."
        case .escalated:
            return "relay escalated — parked; \(state.note ?? "a founder question is open"). No further `pilot handoff` calls are accepted until this is resolved."
        case .stopped:
            return "relay stopped (\(state.stoppedReason ?? "a ceiling was reached")) — no further `pilot handoff` calls are accepted."
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
            return ("CLI_USAGE_ERROR", "--dev-worker <seat|alias> required (no remembered seat for this project) — ready seats: \(readySeats)")
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
            return ("RELAY_INVALID_STATE", "relay is not a Pilot relay (pmMode != external) — use `alln pair relay`/`alln pair relay-resume` instead")
        case .roundInFlight:
            return ("RELAY_ROUND_IN_FLIGHT", "a round is already dispatching for this relay — poll `pilot status --json` until awaitingPM; do not re-dispatch while running (optional: `pilot watch`)")
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
            return ("RELAY_INVALID_STATE", "relay is not a spawned relay (pmMode != spawned) — only a spawned relay can be handed to a piloting session")
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

    private static func failPilotRound(_ error: RelayCoordinator.PilotRoundError) -> Never {
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
}

/// `pilot handoff --json` envelope: the same `RelayJSON` every other relay verb emits,
/// plus the dev's report verbatim when a dev turn delivered in THIS call (nil for a
/// done/escalate/ceiling/stagnation round, or when the dev turn never delivered).
struct PilotHandoffJSON: Encodable {
    let relay: RelayJSON
    let devReport: String?
}

/// `pilot status --json` envelope: relay state plus typed recovery when `.running`.
struct PilotStatusJSON: Encodable {
    let relay: RelayJSON
    let recovery: String?
    let nextActions: [AgentSurfaceNextAction]
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
