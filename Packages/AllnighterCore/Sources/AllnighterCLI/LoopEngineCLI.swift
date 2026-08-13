import Foundation
import AllnighterCore
import AllnighterEngine

/// The Loop control plane (`docs/archive/phases/PM_Relay.md` §6 R-S05):
/// unattended PM↔dev loop — pin baseline, PM turn + verdict, `HandoverGate`, dev
/// turn, repeat until `done`/`escalate`/a ceiling — never by inference.
///
/// Retired `pair relay`/`pair relay-status`/`pair relay-resume` no longer dispatch here
/// (LVC Piece 1, hard cutover) — `LoopCLI` is the live caller, forwarding into
/// `runStatus`/`runStop`/`runResume`/`runAdopt` and the `config:`-based `runRelay`
/// overload below directly. Flag parsing/validation for the retired raw-args shape
/// lives in throwing, store-injectable, exit-free functions
/// (`parseStartConfig`/`parseResumeRequest`) kept for their direct unit tests; only
/// the thin `run*` entry points touch `exit()`.
enum LoopEngineCLI {
    /// LVC-S02b: `alln loop start` (`LoopCLI`) builds `Config` itself — with
    /// `docPath: nil` for a brief-only loop — and dispatches straight through,
    /// without going through `parseStartConfig`'s hard `--doc` requirement (that
    /// requirement is `parseStartConfig`'s own contract, kept for its direct unit
    /// tests; nothing live calls it anymore).
    static func runRelay(config: LoopCoordinator.Config, opts: Options, runtime: ToolRuntime) async {
        if opts.flag("no-wait") {
            await runRelayNoWait(
                config: config, opts: opts, wakeDelivery: DetachedDispatch.validateWakeDelivery(opts))
            return
        }
        _ = DetachedDispatch.validateWakeDelivery(opts)

        // Attended path: runs now and returns its own result (INFORM-never-BLOCK).
        // Deferred wake delivery is gated only on the --no-wait --delivery wake path.

        let coordinator = LoopDispatch.makeCoordinator(runtime: runtime)
        let emitJSON = opts.flag("json")
        let result = await coordinator.run(config: config) { event in
            emit(event, json: emitJSON)
        }
        switch result {
        case .success(let state):
            emitTerminal(state, json: emitJSON)
        case .failure(let refusal):
            failStart(refusal)
        }
    }

    /// RSC-HF: `alln loop --no-wait`. Non-mutating preflight fails loud and spawns
    /// nothing. On success, spawn the same registered `alln loop` verb (no hidden
    /// continuation) and ack only after the child durably claims via `DetachedHandoff`.
    private static func runRelayNoWait(
        config: LoopCoordinator.Config, opts: Options, wakeDelivery: Bool
    ) async {
        let stateStore = LoopStateStore()
        if case .failure(let refusal) = LoopCoordinator.preflightStart(
            projectRoot: config.projectRoot, docPath: config.docPath, brief: config.brief, stateStore: stateStore
        ) {
            failStart(refusal)
        }
        await awaitDetachedAcceptance(
            cwd: config.projectRoot, json: opts.flag("json"), wakeDelivery: wakeDelivery)
    }

    /// Reconciles via `LoopCoordinator.reconcileOrphan` (not a raw `LoopStateStore.load`)
    /// so a `.running` relay whose owner process died mid-round reconciles to `.stopped`
    /// here — works-test hazard #1: "on load/list/status/start".
    static func runStatus(
        _ args: [String],
        stateStore: LoopStateStore = LoopStateStore(),
        threadProjector: LoopThreadProjector? = LoopThreadProjector(),
        runStore: RunStore = RunStore()
    ) {
        guard !args.isEmpty else { usage("relay-status --relay <id> [--wait-for parked|terminal --timeout <seconds>] [--json]") }
        let opts = Options(args)
        guard let loopId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        let wait = parseStatusWait(opts, loopId: loopId)
        func load() -> LoopState {
            let loaded = LoopEngineCLILoad.requireState(id: loopId, store: stateStore)
            return LoopCoordinator.reconcileOrphan(
                loaded, stateStore: stateStore, threadProjector: threadProjector, now: Date.init)
        }

        let state: LoopState
        let waitOutcome: PMTurnStatusWait.Outcome?
        if let wait {
            var observed: LoopState?
            let result = PMTurnStatusWait.wait(
                target: wait.target,
                timeout: wait.timeout,
                readStatus: {
                    let state = load()
                    observed = state
                    return state.status
                }
            )
            guard let observed else {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "loop status waiter returned without observing relay state")
            }
            state = observed
            waitOutcome = result.outcome
        } else {
            state = load()
            waitOutcome = nil
        }

        let pmTurn = PMTurnStatusProjection.load(
            kind: .relay,
            subjectId: state.id,
            atPMBoundary: PMTurnStatusProjection.isRelayPMBoundary(state.status),
            store: PMTurnStore(loopsRootDirectory: stateStore.rootDirectory)
        )
        var json = LoopJSON.project(
            state,
            contractVersion: ContractRegistry.contractVersion,
            pmTurn: pmTurn.pmTurn,
            notes: pmTurn.notes,
            pmTurnDelivery: pmTurn.pmTurnDelivery,
            runStore: runStore
        )
        json.waitOutcome = waitOutcome?.rawValue
        // OUR-S02: same live usage hero as pilot status (active linked dev seat).
        let liveUsage = ObservedUsagePresentation.liveDevUsage(state: state, runStore: runStore)
        let startedAt = state.rounds.last?.startedAt
        let elapsed = (state.status == .running)
            ? startedAt.map { max(0, Int(Date().timeIntervalSince($0))) }
            : nil
        let lastProgress = StreamLiveness.relayStreamLastActivityAt(state: state, runStore: runStore)
        let silence = lastProgress.map { max(0, Int(Date().timeIntervalSince($0))) }
        let hero: String? = {
            guard state.status == .running else { return nil }
            return ObservedUsagePresentation.liveHeroLine(
                ownerAlive: nil,
                silenceAgeSeconds: silence,
                elapsedSeconds: elapsed,
                usagePresentation: liveUsage?.presentation
            )
        }()
        if opts.flag("json") {
            // Additive top-level keys for agents; durable LoopJSON stays status truth.
            var envelope: [String: Any] = [:]
            if let data = try? JSONEncoder().encode(json),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                envelope = obj
            }
            if let liveUsage {
                if let data = try? JSONEncoder().encode(liveUsage),
                   let obj = try? JSONSerialization.jsonObject(with: data) {
                    envelope["observedUsage"] = obj
                }
                envelope["usagePresentation"] = liveUsage.presentation
            }
            if let hero { envelope["liveLine"] = hero }
            if let data = try? JSONSerialization.data(withJSONObject: envelope),
               let s = String(data: data, encoding: .utf8) {
                print(s)
            } else {
                print(AllnighterCLI.jsonString(json))
            }
        } else {
            print(LoopDispatch.humanLoopSummary(json))
            let log = LoopDispatch.humanRoundLog(json)
            if !log.isEmpty { print(log) }
            if let hero { print(hero) }
            if let line = PilotCLI.humanDevLegLine(
                StreamLiveness.devLegProjection(state: state, runStore: runStore)
            ) {
                print(line)
            }
            if let waitOutcome { print("wait outcome: \(waitOutcome.rawValue)") }
        }
        if waitOutcome == .timedOut {
            exit(ContractRegistry.milestone1.processExitCode(forErrorCode: "PM_TURN_WAIT_TIMEOUT"))
        }
    }

    private static func parseStatusWait(
        _ opts: Options, loopId: String
    ) -> (target: PMTurnStatusWait.Target, timeout: TimeInterval)? {
        let waitRaw = opts.value("wait-for")
        let timeoutRaw = opts.value("timeout")
        if waitRaw == nil && timeoutRaw == nil { return nil }
        guard let waitRaw else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--timeout requires --wait-for parked|terminal")
        }
        guard let timeoutRaw else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--wait-for requires --timeout <seconds>")
        }
        guard let target = PMTurnStatusWait.Target(rawValue: waitRaw) else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "loop status supports --wait-for parked|terminal; use `alln loop status \(loopId) --wait-for parked|terminal --timeout <seconds> --json`"
            )
        }
        guard let timeout = TimeInterval(timeoutRaw), timeout >= 0 else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--timeout must be a non-negative number of seconds")
        }
        return (target, timeout)
    }

    static func runResume(
        _ args: [String],
        runtime: ToolRuntime,
        stateStore: LoopStateStore = LoopStateStore(),
        projectStore: ProjectStore = ProjectStore()
    ) async {
        guard !args.isEmpty else { usage("relay-resume --relay <id> --answer <text> [--until HH:MM] [--max-rounds N] [--no-wait] [--json]") }
        let opts = Options(args)

        // LOOP-TWIN: free twin — resolve + report only. Never DetachedDispatch,
        // coordinator.resume, or durable state writes.
        if opts.flag("dry-run") {
            let payload = await dryRunResume(
                opts: opts, stateStore: stateStore, projectStore: projectStore
            )
            print(AllnighterCLI.jsonString(payload))
            return
        }

        let request: (loopId: String, answer: String, priorState: LoopState, config: LoopCoordinator.Config)
        do {
            request = try parseResumeRequest(args, stateStore: stateStore, projectStore: projectStore)
        } catch let error as LoopEngineCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        if opts.flag("no-wait") {
            await runResumeNoWait(
                loopId: request.loopId, founderAnswer: request.answer, config: request.config,
                opts: opts, runtime: runtime, wakeDelivery: DetachedDispatch.validateWakeDelivery(opts)
            )
            return
        }
        _ = DetachedDispatch.validateWakeDelivery(opts)

        // Attended resume — not gated by serve health.

        let coordinator = LoopDispatch.makeCoordinator(runtime: runtime)
        let emitJSON = opts.flag("json")
        let result = await coordinator.resume(
            loopId: request.loopId, founderAnswer: request.answer, config: request.config,
            events: { event in emit(event, json: emitJSON) }
        )
        switch result {
        case .success(let state):
            emitTerminal(state, json: emitJSON)
        case .failure(let refusal):
            failResume(refusal, loopId: request.loopId)
        }
    }

    /// LOOP-TWIN: pure resolve for `loop resume --dry-run`. Load-only — never
    /// reconciles orphans (that writes), never flips status, never dispatches.
    /// Illegal/missing state → `ready: false` + warnings, still a successful dry-run.
    static func dryRunResume(
        opts: Options,
        stateStore: LoopStateStore = LoopStateStore(),
        projectStore: ProjectStore = ProjectStore()
    ) async -> LoopStartDryRunJSON {
        let loopId = opts.value("relay") ?? ""
        let answer = opts.value("answer") ?? ""
        var warnings: [String] = []

        if loopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("missing required --relay / loop-id")
        }
        if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("missing required --answer <text>")
        }
        if opts.value("max-rounds") != nil, parseMaxRounds(opts.value("max-rounds")) == nil {
            warnings.append("--max-rounds must be a positive integer, got \"\(opts.value("max-rounds") ?? "")\"")
        }
        let untilParsed = LoopDispatch.parseUntilValidated(opts.value("until"))
        if let bad = untilParsed.invalid {
            warnings.append("--until could not be parsed: \"\(bad)\"")
        }

        var projectId = ""
        var projectRoot = ""
        var specPath: String?
        var pmOccupant = "?"
        var devOccupant = "?"
        var ready = warnings.isEmpty

        if !loopId.isEmpty {
            switch stateStore.loadResult(id: loopId) {
            case .failure(.notFound):
                warnings.append("loop not found: \(loopId)")
                ready = false
            case .failure(.decodeFailed(let detail)):
                warnings.append(detail.agentMessage)
                ready = false
            case .success(let state):
                projectRoot = state.projectRoot
                projectId = projectStore.resolveFresh(state.projectRoot)?.id
                    ?? AllnighterCLI.resolveProject(state.projectRoot, store: projectStore)?.id
                    ?? ""
                specPath = state.docPath
                pmOccupant = state.isCallerChair ? "caller" : state.pmModelId
                devOccupant = state.devModelId
                // Same eligibility as parseResumeRequest — pure read, including
                // orphaned-running (isOwnerDead is non-mutating).
                let orphaned = state.status == .running && stateStore.isOwnerDead(id: loopId)
                if !(state.isResumable || orphaned) {
                    warnings.append(
                        "loop is not resumable (status: \(state.status.rawValue)) — resume requires escalated or orphan-reconciled stopped"
                    )
                    ready = false
                }
                if let lockWarning = await LoopDryRunSupport.writeLockWarning(projectRoot: state.projectRoot) {
                    warnings.append(lockWarning)
                    // Write lock busy is advisory queue, not a hard refuse — keep ready.
                }
            }
        } else {
            ready = false
        }

        // Usage-level problems keep ready false even when state would allow resume.
        if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || loopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (opts.value("max-rounds") != nil && parseMaxRounds(opts.value("max-rounds")) == nil)
            || untilParsed.invalid != nil {
            ready = false
        }

        let nextCommand = LoopDryRunSupport.resumeCommand(
            loopId: loopId.isEmpty ? "<loop-id>" : loopId,
            answer: answer.isEmpty ? "<text>" : answer,
            maxRounds: opts.value("max-rounds"),
            until: opts.value("until")
        )
        return LoopStartDryRunJSON(
            brief: answer,
            specPath: specPath,
            projectId: projectId,
            projectRoot: projectRoot,
            pm: .init(occupant: pmOccupant, source: "loop"),
            dev: .init(occupant: devOccupant, source: "loop"),
            ready: ready,
            warnings: warnings,
            nextAction: AgentNextAction(
                kind: "startTeamRun",
                label: "Resume the loop for real",
                command: nextCommand
            )
        )
    }

    /// RSC-HF: `alln loop resume --no-wait`. Parent does not mutate — the child runs
    /// the normal registered `loop resume` path (one guarded entry point) and reports
    /// acceptance via `DetachedHandoff` after the durable `.running` claim.
    private static func runResumeNoWait(
        loopId: String, founderAnswer: String, config: LoopCoordinator.Config,
        opts: Options, runtime: ToolRuntime, wakeDelivery: Bool
    ) async {
        _ = (loopId, founderAnswer, runtime) // parsed/validated above; child re-runs the real path
        await awaitDetachedAcceptance(
            cwd: config.projectRoot, json: opts.flag("json"), wakeDelivery: wakeDelivery)
    }

    /// ATL-S02: `alln loop stop --relay <id>` — founder abandonment of a Loop.
    /// Settlement lives in `LoopCoordinator.stop` (exact ten-step order). Exit 0 on
    /// transition or idempotent terminal; never exits 1 just because status is stopped
    /// (that exit class is for ceiling/escalate endings of run/resume, not stop).
    static func runStop(_ args: [String], runtime: ToolRuntime) {
        guard !args.isEmpty else { usage("relay stop --relay <id> [--json]") }
        let opts = Options(args)
        guard let loopId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        let coordinator = LoopDispatch.makeCoordinator(runtime: runtime)
        switch coordinator.stop(loopId: loopId) {
        case .success(let state):
            emitStopSuccess(state, json: opts.flag("json"))
        case .failure(let error):
            failStop(error, loopId: loopId)
        }
    }

    /// `alln loop adopt --relay <id> --pm-model <id>` (docs/phases/Pilot_Relay.md
    /// §5, PL-S06) — adopt (unattended handover): hands a parked Pilot relay to a
    /// spawned PM, then lets the loop run to a terminal state exactly like `alln loop`/
    /// `loop resume`. `projectRoot`/`docPath`/`devModelId` are always read from the
    /// loaded relay (never from a flag here) — an adopt can never silently redirect a
    /// relay at a different doc or repo, same discipline `resume` already follows.
    static func runAdopt(
        _ args: [String],
        runtime: ToolRuntime,
        stateStore: LoopStateStore = LoopStateStore(),
        projectStore: ProjectStore = ProjectStore()
    ) async {
        guard !args.isEmpty else { usage("relay adopt --relay <id> --pm-model <modelId> [--max-rounds N] [--until HH:MM] [--no-wait] [--json]") }
        let opts = Options(args)
        guard let loopId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        guard let pmModelId = opts.value("pm-model") else { fail(.missingRequired("--pm-model <modelId>")) }
        guard let maxRounds = parseMaxRounds(opts.value("max-rounds")) else {
            fail(.invalidMaxRounds(opts.value("max-rounds") ?? ""))
        }
        let untilParsed = LoopDispatch.parseUntilValidated(opts.value("until"))
        if let bad = untilParsed.invalid { fail(.invalidUntil(bad)) }

        let priorState = LoopEngineCLILoad.requireState(id: loopId, store: stateStore)
        let projectId = AllnighterCLI.resolveProject(priorState.projectRoot, store: projectStore)?.id
        let config = LoopCoordinator.Config(
            projectRoot: priorState.projectRoot, projectId: projectId, docPath: priorState.docPath,
            pmModelId: pmModelId, devModelId: priorState.devModelId,
            maxRounds: maxRounds, until: untilParsed.value
        )

        if opts.flag("no-wait") {
            await runAdoptNoWait(
                loopId: loopId, pmModelId: pmModelId, config: config, opts: opts, runtime: runtime,
                wakeDelivery: DetachedDispatch.validateWakeDelivery(opts))
            return
        }
        _ = DetachedDispatch.validateWakeDelivery(opts)

        // Attended adopt — not gated by serve health.

        let coordinator = LoopDispatch.makeCoordinator(runtime: runtime)
        let emitJSON = opts.flag("json")
        let result = await coordinator.adopt(loopId: loopId, pmModelId: pmModelId, config: config) { event in
            emit(event, json: emitJSON)
        }
        switch result {
        case .success(let state):
            emitTerminal(state, json: emitJSON)
        case .failure(let error):
            failAdopt(error)
        }
    }

    /// RSC-HF: `alln loop adopt --no-wait`. Parent does not mutate — child runs the
    /// normal registered `loop adopt` path and reports acceptance after claim.
    private static func runAdoptNoWait(
        loopId: String, pmModelId: String, config: LoopCoordinator.Config,
        opts: Options, runtime: ToolRuntime, wakeDelivery: Bool
    ) async {
        _ = (loopId, pmModelId, runtime)
        await awaitDetachedAcceptance(
            cwd: config.projectRoot, json: opts.flag("json"), wakeDelivery: wakeDelivery)
    }

    /// Shared `--no-wait` accept wait: spawn same argv minus `--no-wait`, ack only after
    /// the child writes `DetachedHandoff` accepted/refused.
    ///
    /// `--delivery wake` is a deferred obligation the supervised daemon claims —
    /// refuse loudly via `ServeRequirement` before any handoff write when serve
    /// is not actively healthy (queue-honesty). Plain `--no-wait` is not gated:
    /// the detached child runs now and returns its own result.
    private static func awaitDetachedAcceptance(cwd: String, json: Bool, wakeDelivery: Bool) async {
        if wakeDelivery {
            requireServeForDeferredObligation(reason: "pmTurnWake")
        }
        do {
            switch try DetachedDispatch.launchAndAwaitAcceptance(cwd: cwd, arguments: DetachedDispatch.childArguments()) {
            case .accepted(let id, let pid):
                emitDispatchAck(kind: "relay", id: id, pid: pid, json: json, wakeDelivery: wakeDelivery)
            case .refused(_, let code, let message, _):
                AllnighterCLI.fail(code: code, message: message)
            case .timedOut:
                AllnighterCLI.fail(
                    code: "INTERNAL_ERROR",
                    message: "detached child did not accept within the handoff window"
                )
            }
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not dispatch background relay: \(error)")
        }
    }

    /// Single product refusal for a deferred obligation that only serve will claim.
    private static func requireServeForDeferredObligation(reason: String) {
        if case .failure(let refusal) = ServeRequirement().require(reason: reason) {
            AllnighterCLI.fail(code: refusal.code, message: refusal.message)
        }
    }

    // MARK: - Parsing (throwing, exit-free — unit-testable)

    enum LoopEngineCLIError: Error, Equatable {
        case missingRequired(String)
        case invalidMaxRounds(String)
        case invalidUntil(String)
        case invalidIdleTimeout(String)
        case projectNotFound(String)
        case relayNotFound(String)
        case relayStateDecodeFailed(LoopStateStore.RelayLoadFailure.DecodeFailed)
        case relayNotEscalated(status: String)
        /// Structured exact-id failure (`--pm-model` / `--dev-model`) — carries the
        /// same envelope `AllnighterCLI.failExactId` renders (candidates/suggestions/
        /// nextAction), so the entry point can render it byte-for-byte unchanged
        /// instead of losing that detail through the generic `errorEnvelope` mapping
        /// (mirrors `PilotSeatResolver.Error.exactId`).
        case workerNotAvailable(ExactIdResolver.Failure)
        /// OCL-S07: a local Ollama seat cannot hold the PM chair.
        case localSeatCannotLead(String)
        /// ATL-S01: both `--message` and `--message-file` present.
        case kickoffMessageMutex
        /// ATL-S01: `--message-file` path missing or unreadable.
        case kickoffMessageFileUnreadable(String)
        /// ATL-S01: either flag present but body empty after trim.
        case kickoffMessageEmpty
    }

    static func parseStartConfig(
        _ args: [String],
        projectStore: ProjectStore = ProjectStore(),
        models: [Model] = []
    ) throws -> LoopCoordinator.Config {
        let opts = Options(args)
        guard let docPath = opts.value("doc") else { throw LoopEngineCLIError.missingRequired("--doc <path>") }
        guard let projectToken = opts.value("project") else { throw LoopEngineCLIError.missingRequired("--project <id|path>") }
        guard let pmModelId = opts.value("pm-model") else { throw LoopEngineCLIError.missingRequired("--pm-model <modelId>") }
        guard let devModelId = opts.value("dev-model") else { throw LoopEngineCLIError.missingRequired("--dev-model <modelId>") }
        // Empty `models` (the default) falls back to the live catalog for real
        // invocations; tests inject a hermetic fixture instead (mirrors PilotCLI's
        // `parseStartConfig(models:)` seam) — never reads live user config in tests.
        let catalogModels = models.isEmpty ? ModelCatalog.resolvedModels(registry: DefaultConfig.registry) : models
        switch ExactIdResolver.resolveWorker(pmModelId, flag: "--pm-model", models: catalogModels) {
        case .failure(let failure):
            throw LoopEngineCLIError.workerNotAvailable(failure)
        case .success(let model):
            if let refusal = LoopLocalSeatPolicy.pmRefusal(for: model) {
                throw LoopEngineCLIError.localSeatCannotLead(refusal)
            }
        }
        if case .failure(let failure) = ExactIdResolver.resolveWorker(devModelId, flag: "--dev-model", models: catalogModels) {
            throw LoopEngineCLIError.workerNotAvailable(failure)
        }
        guard let project = AllnighterCLI.resolveProject(projectToken, store: projectStore) else {
            throw LoopEngineCLIError.projectNotFound(projectToken)
        }
        guard let maxRounds = parseMaxRounds(opts.value("max-rounds")) else {
            throw LoopEngineCLIError.invalidMaxRounds(opts.value("max-rounds") ?? "")
        }
        let untilParsed = LoopDispatch.parseUntilValidated(opts.value("until"))
        if let bad = untilParsed.invalid { throw LoopEngineCLIError.invalidUntil(bad) }
        // PO-F7: reuses PO-F5's `alln run --idle-timeout` parse helper — no second idle system.
        let idleParsed = RunCLI.parseIdleTimeoutSeconds(opts.value("idle-timeout"))
        if let error = idleParsed.error { throw LoopEngineCLIError.invalidIdleTimeout(error) }
        let kickoffMessage = try parseKickoffMessage(opts)
        return LoopCoordinator.Config(
            projectRoot: project.normalizedRootPath,
            projectId: project.id,
            docPath: docPath,
            pmModelId: pmModelId,
            devModelId: devModelId,
            maxRounds: maxRounds,
            until: untilParsed.value,
            devTurnIdleTimeoutSeconds: idleParsed.value,
            kickoffMessage: kickoffMessage
        )
    }

    /// ATL-S01: optional kickoff brief from `--message` or `--message-file`.
    /// Neither flag → `nil` (back-compat). Both → mutex error. Flag present but
    /// empty-after-trim → refuse. File missing/unreadable → refuse. No silent truncation.
    static func parseKickoffMessage(_ opts: Options) throws -> String? {
        let inline = opts.value("message")
        let filePath = opts.value("message-file")
        switch (inline, filePath) {
        case (nil, nil):
            return nil
        case (.some, .some):
            throw LoopEngineCLIError.kickoffMessageMutex
        case (.some(let text), nil):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LoopEngineCLIError.kickoffMessageEmpty
            }
            return text
        case (nil, .some(let path)):
            guard let data = FileManager.default.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8) else {
                throw LoopEngineCLIError.kickoffMessageFileUnreadable(path)
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LoopEngineCLIError.kickoffMessageEmpty
            }
            return text
        }
    }

    static func parseResumeRequest(
        _ args: [String],
        stateStore: LoopStateStore = LoopStateStore(),
        projectStore: ProjectStore = ProjectStore()
    ) throws -> (loopId: String, answer: String, priorState: LoopState, config: LoopCoordinator.Config) {
        let opts = Options(args)
        guard let loopId = opts.value("relay") else { throw LoopEngineCLIError.missingRequired("--relay <id>") }
        guard let answer = opts.value("answer"), !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LoopEngineCLIError.missingRequired("--answer <text>")
        }
        let priorState: LoopState
        switch stateStore.loadResult(id: loopId) {
        case .success(let state):
            priorState = state
        case .failure(.notFound):
            throw LoopEngineCLIError.relayNotFound(loopId)
        case .failure(.decodeFailed(let detail)):
            throw LoopEngineCLIError.relayStateDecodeFailed(detail)
        }
        // `priorState` here is the raw persisted read — `LoopCoordinator.resume` (which
        // this request feeds) is what durably reconciles a dead-owner `.running` relay to
        // `.stopped`; this pre-check only needs to know THAT it would be eligible, via the
        // same owner.pid liveness signal, so a founder never sees a stale "not escalated"
        // rejection for a relay that's actually about to reconcile-and-resume (works-test
        // hazard #1: "escalated-only was too narrow").
        let orphaned = priorState.status == .running && stateStore.isOwnerDead(id: loopId)
        guard priorState.isResumable || orphaned else {
            throw LoopEngineCLIError.relayNotEscalated(status: priorState.status.rawValue)
        }
        guard let maxRounds = parseMaxRounds(opts.value("max-rounds")) else {
            throw LoopEngineCLIError.invalidMaxRounds(opts.value("max-rounds") ?? "")
        }
        // The coordinator itself re-derives projectRoot/docPath/pmModelId/devModelId
        // from the persisted state on resume (LoopCoordinator.resume) — resolving the
        // project here too only recovers a real `projectId` for the RunRequest;
        // `nil` degrades gracefully if the project entry can't be found.
        let untilParsed = LoopDispatch.parseUntilValidated(opts.value("until"))
        if let bad = untilParsed.invalid { throw LoopEngineCLIError.invalidUntil(bad) }
        let projectId = AllnighterCLI.resolveProject(priorState.projectRoot, store: projectStore)?.id
        let config = LoopCoordinator.Config(
            projectRoot: priorState.projectRoot,
            projectId: projectId,
            docPath: priorState.docPath,
            pmModelId: priorState.pmModelId,
            devModelId: priorState.devModelId,
            maxRounds: maxRounds,
            until: untilParsed.value
        )
        return (loopId, answer, priorState, config)
    }

    static func parseMaxRounds(_ raw: String?) -> Int? {
        guard let raw else { return 20 }
        guard let value = Int(raw), value > 0 else { return nil }
        return value
    }

    // MARK: - Output

    private static func emit(_ event: LoopCoordinator.RelayEvent, json: Bool) {
        if json {
            print(LoopDispatch.progressJSONLine(event))
        } else {
            print(LoopDispatch.humanProgressLine(event))
        }
    }

    /// Every detached Relay verb returns the one waiter for its terminal PM Turn.
    private static func emitDispatchAck(
        kind: String, id: String, pid: Int32, json: Bool, wakeDelivery: Bool
    ) {
        let delivery = wakeDelivery
            ? DetachedDispatch.wakeDelivery()
            : DetachedDispatch.waitDelivery(
                kind: kind, id: id, commandPrefix: DetachedDispatch.commandPrefix())
        if json {
            print(AllnighterCLI.jsonLine(DetachedDispatchJSON(
                kind: kind, id: id, status: "dispatched", pid: pid, delivery: delivery)))
        } else {
            if let command = delivery.command {
                print("dispatched (pid \(pid)) — wait for delivery with `\(command)`")
            } else {
                print("dispatched (pid \(pid)) — PM Turn wake delivery configured")
            }
        }
    }

    /// Prints the final `LoopJSON` and exits non-zero for the two "founder must look
    /// at this" endings — `escalated` (a real question) and `stopped` (a ceiling fired,
    /// PM_Relay.md §5 item 3) — so scripting/automation can tell a clean `done` apart
    /// from either. `running` never reaches here: `run`/`resume` only return once the
    /// loop hits a terminal `LoopState`.
    private static func emitTerminal(_ state: LoopState, json: Bool) {
        emitLoopJSON(state, json: json)
        if state.status == .escalated || state.status == .stopped { exit(1) }
    }

    /// ATL-S02: founder stop always exits 0 on success (including idempotent
    /// done/stopped) — the founder asked to stop; status=stopped is the success case.
    private static func emitStopSuccess(_ state: LoopState, json: Bool) {
        emitLoopJSON(state, json: json)
        exit(0)
    }

    private static func emitLoopJSON(_ state: LoopState, json: Bool) {
        let pmTurn = PMTurnStatusProjection.load(
            kind: .relay,
            subjectId: state.id,
            atPMBoundary: true,
            store: PMTurnStore()
        )
        let relayJSON = LoopJSON.project(
            state,
            contractVersion: ContractRegistry.contractVersion,
            pmTurn: pmTurn.pmTurn,
            notes: pmTurn.notes,
            pmTurnDelivery: pmTurn.pmTurnDelivery
        )
        if json {
            print(AllnighterCLI.jsonLine(relayJSON))
        } else {
            print(LoopDispatch.humanLoopSummary(relayJSON))
        }
    }

    // MARK: - Exit funnel

    static func fail(_ error: LoopEngineCLIError) -> Never {
        // `.workerNotAvailable` renders through the same `failExactId` funnel the old
        // in-parse `exit()` call used — candidates/suggestions/nextAction included —
        // so real invocations see byte-for-byte the same envelope as before.
        if case .workerNotAvailable(let failure) = error {
            DetachedHandoff.reportRefused(code: failure.code, message: failure.message)
            AllnighterCLI.failExactId(failure)
        }
        let (code, message) = errorEnvelope(error)
        DetachedHandoff.reportRefused(code: code, message: message)
        AllnighterCLI.fail(code: code, message: message)
    }

    static func errorEnvelope(_ error: LoopEngineCLIError) -> (code: String, message: String) {
        switch error {
        case .workerNotAvailable(let failure):
            return (failure.code, failure.message)
        case .localSeatCannotLead(let message):
            return (LoopLocalSeatPolicy.errorCode, message)
        case .missingRequired(let flag):
            return ("CLI_USAGE_ERROR", "\(flag) required")
        case .invalidMaxRounds(let raw):
            return ("CLI_USAGE_ERROR", "--max-rounds must be a positive integer, got '\(raw)'")
        case .invalidUntil(let raw):
            return ("CLI_USAGE_ERROR", "--until must be HH:MM (24-hour), got '\(raw)'")
        case .invalidIdleTimeout(let message):
            return ("CLI_USAGE_ERROR", message)
        case .projectNotFound(let token):
            return ("PROJECT_NOT_FOUND", "project not found: \(token)")
        case .relayNotFound(let id):
            return ("RELAY_NOT_FOUND", "relay not found: \(id)")
        case .relayStateDecodeFailed(let detail):
            return ("RELAY_STATE_DECODE_FAILED", detail.agentMessage)
        case .relayNotEscalated(let status):
            return ("RELAY_INVALID_STATE", "relay is \(status), not resumable — only an escalated relay, or one reconciled after its owner process died, can be resumed")
        case .kickoffMessageMutex:
            return ("CLI_USAGE_ERROR", "--message and --message-file are mutually exclusive")
        case .kickoffMessageFileUnreadable(let path):
            return ("CLI_USAGE_ERROR", "--message-file unreadable: \(path)")
        case .kickoffMessageEmpty:
            return ("CLI_USAGE_ERROR", "kickoff brief is required when --message/--message-file is set")
        }
    }

    private static func failAdopt(_ error: LoopCoordinator.AdoptError) -> Never {
        let (code, message) = adoptErrorEnvelope(error)
        DetachedHandoff.reportRefused(code: code, message: message)
        AllnighterCLI.fail(code: code, message: message)
    }

    private static func failStop(_ error: LoopCoordinator.StopRefusal, loopId: String) -> Never {
        let (code, message) = stopErrorEnvelope(error, loopId: loopId)
        DetachedHandoff.reportRefused(id: loopId, code: code, message: message)
        AllnighterCLI.fail(code: code, message: message)
    }

    static func stopErrorEnvelope(
        _ error: LoopCoordinator.StopRefusal, loopId: String
    ) -> (code: String, message: String) {
        switch error {
        case .relayNotFound:
            return ("RELAY_NOT_FOUND", "relay not found: \(loopId)")
        case .stopFailed(let detail):
            return (
                "RELAY_STOP_FAILED",
                "could not settle founder stop for \(loopId): \(detail) — inspect with `alln ps --json` and retry; do not invent resume"
            )
        }
    }

    static func adoptErrorEnvelope(_ error: LoopCoordinator.AdoptError) -> (code: String, message: String) {
        switch error {
        case .relayNotFound:
            return ("RELAY_NOT_FOUND", "relay not found")
        case .notPilotRelay:
            return ("RELAY_INVALID_STATE", "relay is not a Pilot relay (caller doesn't hold the PM seat) — only a Pilot relay can be adopted by a spawned PM")
        case .notAdoptable(let status):
            return ("RELAY_INVALID_STATE", "relay is \(status), not adoptable — only a parked Pilot relay (awaitingPM or escalated) can be adopted")
        case .roundInFlight:
            return ("RELAY_ROUND_IN_FLIGHT", "another process is already dispatching a round for this relay — wait with `alln loop status <loop-id> --wait-for terminal --timeout 7200 --json` and retry once it settles")
        case .journalUnavailable:
            return ("RELAY_JOURNAL_UNAVAILABLE", "could not persist relay claim — journal write failed")
        }
    }

    /// RSC-S01: `LoopCoordinator.resume`'s failure channel. `.relayNotFound`/
    /// `.notResumable` mirror the existing pre-check in `parseResumeRequest` (which
    /// normally catches these first); `.roundInFlight` is new — a concurrent
    /// `resume`/`adopt` already holds this relay's dispatch lock.
    private static func failResume(_ error: LoopCoordinator.DispatchRefusal, loopId: String) -> Never {
        let (code, message) = resumeErrorEnvelope(error, loopId: loopId)
        DetachedHandoff.reportRefused(id: loopId, code: code, message: message)
        AllnighterCLI.fail(code: code, message: message)
    }

    static func resumeErrorEnvelope(
        _ error: LoopCoordinator.DispatchRefusal, loopId: String
    ) -> (code: String, message: String) {
        switch error {
        case .relayNotFound:
            return ("RELAY_NOT_FOUND", "relay not found: \(loopId)")
        case .notResumable(let status):
            return ("RELAY_INVALID_STATE", "relay is \(status), not resumable — only an escalated relay, or one reconciled after its owner process died, can be resumed")
        case .roundInFlight:
            return ("RELAY_ROUND_IN_FLIGHT", "another process is already dispatching a round for this relay — wait with `alln loop status <loop-id> --wait-for terminal --timeout 7200 --json` and retry once it settles")
        case .alreadyActive(let existingRelayId):
            // Unreachable from `resume` — `.alreadyActive` is only ever produced by
            // `LoopCoordinator.run`'s start-time duplicate guard (RSC-S02). Kept for
            // `DispatchRefusal`'s exhaustive switch, not a real resume outcome.
            return ("RELAY_ALREADY_ACTIVE", "a relay is already running for this project + doc: \(existingRelayId)")
        case .journalUnavailable:
            return ("RELAY_JOURNAL_UNAVAILABLE", "could not persist relay claim — journal write failed")
        }
    }

    /// RSC-S02: `LoopCoordinator.run`'s failure channel. `.alreadyActive` is the only
    /// case `run` ever actually produces (a live-owner `.running` relay already exists
    /// on this normalized root + doc) — `.relayNotFound`/`.notResumable`/`.roundInFlight`
    /// are unreachable from a fresh start, kept only for `DispatchRefusal`'s exhaustive
    /// switch (they're `resume`/`adopt`'s outcomes, not `run`'s).
    private static func failStart(_ error: LoopCoordinator.DispatchRefusal) -> Never {
        let (code, message) = startErrorEnvelope(error)
        DetachedHandoff.reportRefused(code: code, message: message)
        AllnighterCLI.fail(code: code, message: message)
    }

    static func startErrorEnvelope(
        _ error: LoopCoordinator.DispatchRefusal
    ) -> (code: String, message: String) {
        switch error {
        case .alreadyActive(let existingRelayId):
            return (
                "RELAY_ALREADY_ACTIVE",
                "a relay is already running for this project + doc: \(existingRelayId) — read it with `alln loop status \(existingRelayId) --json`, resume or adopt it, or wait; do not start a second relay on the same doc"
            )
        case .relayNotFound, .notResumable, .roundInFlight:
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "unexpected DispatchRefusal from LoopCoordinator.run: \(error)")
        case .journalUnavailable:
            return ("RELAY_JOURNAL_UNAVAILABLE", "could not persist relay claim — journal write failed")
        }
    }

    private static func usage(_ detail: String) -> Never {
        FileHandle.standardError.write(Data("usage: alln pair \(detail)\n".utf8))
        exit(2)
    }
}
