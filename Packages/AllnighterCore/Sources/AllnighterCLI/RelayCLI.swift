import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln pair relay` / `pair relay-status` / `pair relay-resume` — the PM Relay
/// control plane (docs/phases/PM_Relay.md §6 R-S05). Unattended PM↔dev loop:
/// pin baseline, PM turn + verdict, `HandoverGate`, dev turn, repeat until
/// `done`/`escalate`/a ceiling — never by inference.
///
/// Flag parsing/validation lives in throwing, store-injectable, exit-free
/// functions (`parseStartConfig`/`parseResumeRequest`) — the same shape as
/// `PairCLI.beginJSON` — so the recovery ladder is unit-testable without a
/// subprocess; only the thin `run*` entry points touch `exit()`.
enum RelayCLI {
    static func runRelay(_ args: [String], runtime: ToolRuntime) async {
        // "pair relay adopt" is a nested verb (mirrors "pair pilot start|handoff|…"),
        // not a flag on "pair relay" — every other flag here starts with "--", so this
        // check can never misfire against a real start invocation.
        if args.first == "adopt" {
            await runAdopt(Array(args.dropFirst()), runtime: runtime)
            return
        }
        guard !args.isEmpty else { usage("relay --doc <path> --project <id|path> --pm-worker <modelId> --dev-worker <modelId> [--until HH:MM] [--max-rounds N] [--idle-timeout <seconds>] [--no-wait] [--json]") }
        let opts = Options(args)
        let config: RelayCoordinator.Config
        do {
            config = try parseStartConfig(args, models: runtime.models)
        } catch let error as RelayCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        if opts.flag("no-wait") {
            await runRelayNoWait(config: config, opts: opts)
            return
        }

        // URN-S02: guarantee a live notifier before dispatching a real dev turn.
        ServeAutoLaunchCLI.reportToStderr(ServeAutoLaunchCLI.ensureRunning(opts))

        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
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

    /// RSC-S03: `pair relay --no-wait`. `RelayCoordinator.preflightStart` is a
    /// non-mutating, lock-free scan (its own doc: "not a guarantee against a start
    /// that lands between the check and the real call") — a foreground ack-safety
    /// check, not a replacement for the real guarded dispatch. A refusal here fails
    /// loud and spawns nothing. On success, the relay id is pre-minted so the ack can
    /// name it (`RelayCoordinator.mintRelayId()` — the child is told to use this exact
    /// id via the hidden `relay-start-continue` verb's `--relay-id`, never a public
    /// flag on `pair relay` itself, so a normal foreground start can never accidentally
    /// collide two relays onto one id). The child then calls `RelayCoordinator.run`
    /// for real, which re-does the preflight+lock+persist inside itself — exactly
    /// mirroring how Pilot's foreground `preflightExternalRound` doesn't replace the
    /// child's own real dispatch.
    private static func runRelayNoWait(config: RelayCoordinator.Config, opts: Options) async {
        let stateStore = RelayStateStore()
        if case .failure(let refusal) = RelayCoordinator.preflightStart(
            projectRoot: config.projectRoot, docPath: config.docPath, stateStore: stateStore
        ) {
            failStart(refusal)
        }
        let relayId = RelayCoordinator.mintRelayId()
        var childArgs = DetachedDispatch.childArguments()
        // `runRelay` is only ever reached via "pair relay …" (PairCLI routes "relay"
        // here before this function can run), so `childArgs` always starts with
        // exactly these two tokens — swap in the hidden continuation verb so the
        // child's `--relay-id` never has to be a registered, publicly reachable flag.
        if childArgs.count >= 2, childArgs[0] == "pair", childArgs[1] == "relay" {
            childArgs[1] = "relay-start-continue"
        }
        childArgs += ["--relay-id", relayId]
        do {
            let process = try DetachedDispatch.launch(cwd: config.projectRoot, arguments: childArgs)
            emitDispatchAck(kind: "relay", id: relayId, pid: process.processIdentifier, json: opts.flag("json"))
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not dispatch background relay: \(error)")
        }
    }

    /// RSC-S03 hidden continuation verb (`pair relay-start-continue`, never registered
    /// in `ContractRegistry` — not a public command, no help entry, fails closed like
    /// any other unrecognized invocation if typed by hand beyond what's written here).
    /// Only ever spawned by `runRelayNoWait` above. Re-parses the SAME flags `pair
    /// relay` accepts (`parseStartConfig` — one parser, not a second one) plus
    /// `--relay-id`, then calls the real, fully-guarded `RelayCoordinator.run`.
    static func runStartContinue(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let relayId = opts.value("relay-id") else { exit(2) }
        let config: RelayCoordinator.Config
        do {
            config = try parseStartConfig(args, models: runtime.models)
        } catch {
            exit(2)
        }
        ServeAutoLaunchCLI.reportToStderr(ServeAutoLaunchCLI.ensureRunning(opts))
        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        _ = await coordinator.run(config: config, id: relayId)
    }

    /// Reconciles via `RelayCoordinator.reconcileOrphan` (not a raw `RelayStateStore.load`)
    /// so a `.running` relay whose owner process died mid-round reconciles to `.stopped`
    /// here — works-test hazard #1: "on load/list/status/start".
    static func runStatus(
        _ args: [String],
        stateStore: RelayStateStore = RelayStateStore(),
        threadProjector: RelayThreadProjector? = RelayThreadProjector()
    ) {
        guard !args.isEmpty else { usage("relay-status --relay <id> [--json]") }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        guard let loaded = stateStore.load(id: relayId) else { fail(.relayNotFound(relayId)) }
        let state = RelayCoordinator.reconcileOrphan(
            loaded, stateStore: stateStore, threadProjector: threadProjector, now: Date.init)

        let json = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(json))
        } else {
            print(RelayDispatch.humanRelaySummary(json))
            let log = RelayDispatch.humanRoundLog(json)
            if !log.isEmpty { print(log) }
        }
    }

    static func runResume(_ args: [String], runtime: ToolRuntime) async {
        guard !args.isEmpty else { usage("relay-resume --relay <id> --answer <text> [--until HH:MM] [--max-rounds N] [--no-wait] [--json]") }
        let opts = Options(args)
        let request: (relayId: String, answer: String, priorState: RelayState, config: RelayCoordinator.Config)
        do {
            request = try parseResumeRequest(args)
        } catch let error as RelayCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        if opts.flag("no-wait") {
            await runResumeNoWait(
                relayId: request.relayId, founderAnswer: request.answer, config: request.config,
                opts: opts, runtime: runtime
            )
            return
        }

        // URN-S02: guarantee a live notifier before dispatching a real dev turn.
        ServeAutoLaunchCLI.reportToStderr(ServeAutoLaunchCLI.ensureRunning(opts))

        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        let emitJSON = opts.flag("json")
        let result = await coordinator.resume(
            relayId: request.relayId, founderAnswer: request.answer, config: request.config,
            events: { event in emit(event, json: emitJSON) }
        )
        switch result {
        case .success(let state):
            emitTerminal(state, json: emitJSON)
        case .failure(let refusal):
            failResume(refusal, relayId: request.relayId)
        }
    }

    /// RSC-S03: `pair relay-resume --no-wait`. Unlike `pair relay` start, `resume`'s
    /// own correctness IS the mutate-under-lock step (load → check → flip `.running` →
    /// persist) — there is no cheaper non-mutating preflight that would tell the truth,
    /// so the foreground does the REAL guard (`RelayCoordinator.resumeGuard`, the exact
    /// same code `resume` itself calls — one guard implementation either way) before
    /// acking, then hands the round loop off to a detached child instead of running it
    /// in this process. The child never re-runs the guard (it would incorrectly see
    /// `.running` and refuse itself) — it loads the already-flipped state and just
    /// continues (`RelayCoordinator.continueRound`, via the hidden `relay-continue`
    /// verb). A guard refusal fails loud through the SAME `DispatchRefusal` channel
    /// `failResume` already renders and spawns nothing.
    private static func runResumeNoWait(
        relayId: String, founderAnswer: String, config: RelayCoordinator.Config,
        opts: Options, runtime: ToolRuntime
    ) async {
        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        // RSC-S03 hardening: mint a one-time dispatch token — the child (`relay-continue`
        // below) must present it back before `continueRound` will run anything.
        switch coordinator.resumeGuard(relayId: relayId, founderAnswer: founderAnswer, config: config, mintDispatchToken: true) {
        case .failure(let refusal):
            failResume(refusal, relayId: relayId)
        case .success(let (flipped, resumedConfig, dispatchToken)):
            guard let dispatchToken else {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "resumeGuard did not mint a dispatch token for a --no-wait continuation")
            }
            var childArgs = [
                "pair", "relay-continue", "--relay", relayId,
                "--max-rounds", String(resumedConfig.maxRounds),
                "--dispatch-token", dispatchToken,
            ]
            if let rawUntil = opts.value("until") { childArgs += ["--until", rawUntil] }
            do {
                let process = try DetachedDispatch.launch(cwd: flipped.projectRoot, arguments: childArgs)
                // RSC-S03 hot-fix: correct `owner.pid` from this foreground's own pid
                // (stamped by `resumeGuard`'s persist above) to the just-launched
                // child's real pid — see `RelayStateStore.restampOwner`'s doc comment.
                // Synchronous, before this process's own imminent exit, so the window
                // where `owner.pid` names a dead/dying process collapses to ~zero.
                RelayStateStore().restampOwner(id: relayId, pid: process.processIdentifier)
                emitDispatchAck(kind: "relay", id: relayId, pid: process.processIdentifier, json: opts.flag("json"))
            } catch {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not dispatch background relay: \(error)")
            }
        }
    }

    /// RSC-S03 hidden continuation verb (`pair relay-continue`, never registered in
    /// `ContractRegistry`) shared by `resume`/`adopt`'s `--no-wait`: by the time
    /// either has flipped a relay to `.running` under lock, continuing the round loop
    /// no longer cares which of the two got it there — both just need the relay id,
    /// the ceilings for this stretch, and (adopt only) the one-time adoption note.
    /// `--adoption-note-b64` is base64 so the note's own text (which can legitimately
    /// contain anything, including a leading "--") is never mistaken for a flag —
    /// `Process.arguments` needs no shell-escaping, but this file's own `Options`
    /// parser still splits on "--" prefixes.
    static func runContinue(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { exit(2) }
        guard let maxRounds = parseMaxRounds(opts.value("max-rounds")) else { exit(2) }
        // RSC-S03 hardening: the one-time token `resumeGuard`/`adoptGuard` minted and
        // handed only to the child this call is. No token, no run — see
        // `RelayCoordinator.continueRound`'s doc comment for why this exists.
        guard let dispatchToken = opts.value("dispatch-token") else { exit(2) }
        let untilParsed = RelayDispatch.parseUntilValidated(opts.value("until"))
        var adoptionNote: String?
        if let encoded = opts.value("adoption-note-b64"), let data = Data(base64Encoded: encoded) {
            adoptionNote = String(data: data, encoding: .utf8)
        }
        let stateStore = RelayStateStore()
        guard let state = stateStore.load(id: relayId) else { exit(1) }
        ServeAutoLaunchCLI.reportToStderr(ServeAutoLaunchCLI.ensureRunning(opts))
        let projectId = AllnighterCLI.resolveProject(state.projectRoot, store: ProjectStore())?.id
        let config = RelayCoordinator.Config(
            projectRoot: state.projectRoot, projectId: projectId, docPath: state.docPath,
            pmWorkerId: state.pmWorkerId, devWorkerId: state.devWorkerId,
            maxRounds: maxRounds, until: untilParsed.value
        )
        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        let result = await coordinator.continueRound(
            relayId: relayId, dispatchToken: dispatchToken, config: config, adoptionNote: adoptionNote
        )
        if case .failure = result {
            // Refused: wrong/missing/consumed token, relay not `.running`, or another
            // process holds the lock. Never crash, never silently no-op — a clean,
            // honest non-zero exit (this verb is hidden/unregistered; there is no
            // founder-facing error envelope to render for it).
            exit(1)
        }
    }

    /// `pair relay adopt --relay <id> --pm-worker <id>` (docs/phases/Pilot_Relay.md
    /// §5, PL-S06) — adopt (unattended handover): hands a parked Pilot relay to a
    /// spawned PM, then lets the loop run to a terminal state exactly like `relay`/
    /// `relay-resume`. `projectRoot`/`docPath`/`devWorkerId` are always read from the
    /// loaded relay (never from a flag here) — an adopt can never silently redirect a
    /// relay at a different doc or repo, same discipline `resume` already follows.
    static func runAdopt(_ args: [String], runtime: ToolRuntime) async {
        guard !args.isEmpty else { usage("relay adopt --relay <id> --pm-worker <modelId> [--max-rounds N] [--until HH:MM] [--no-wait] [--json]") }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        guard let pmWorkerId = opts.value("pm-worker") else { fail(.missingRequired("--pm-worker <modelId>")) }
        guard let maxRounds = parseMaxRounds(opts.value("max-rounds")) else {
            fail(.invalidMaxRounds(opts.value("max-rounds") ?? ""))
        }
        let untilParsed = RelayDispatch.parseUntilValidated(opts.value("until"))
        if let bad = untilParsed.invalid { fail(.invalidUntil(bad)) }

        let stateStore = RelayStateStore()
        guard let priorState = stateStore.load(id: relayId) else { fail(.relayNotFound(relayId)) }
        let projectId = AllnighterCLI.resolveProject(priorState.projectRoot, store: ProjectStore())?.id
        let config = RelayCoordinator.Config(
            projectRoot: priorState.projectRoot, projectId: projectId, docPath: priorState.docPath,
            pmWorkerId: pmWorkerId, devWorkerId: priorState.devWorkerId,
            maxRounds: maxRounds, until: untilParsed.value
        )

        if opts.flag("no-wait") {
            await runAdoptNoWait(relayId: relayId, pmWorkerId: pmWorkerId, config: config, opts: opts, runtime: runtime)
            return
        }

        // URN-S02: guarantee a live notifier before dispatching a real dev turn.
        // Reachable both directly (`pair relay adopt`) and via `runRelay`'s
        // early redirect — this is the only place the check runs for adopt.
        ServeAutoLaunchCLI.reportToStderr(ServeAutoLaunchCLI.ensureRunning(opts))

        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        let emitJSON = opts.flag("json")
        let result = await coordinator.adopt(relayId: relayId, pmWorkerId: pmWorkerId, config: config) { event in
            emit(event, json: emitJSON)
        }
        switch result {
        case .success(let state):
            emitTerminal(state, json: emitJSON)
        case .failure(let error):
            failAdopt(error)
        }
    }

    /// RSC-S03: `pair relay adopt --no-wait`. Same shape as `runResumeNoWait` — `adopt`'s
    /// own correctness is the mutate-under-lock step, so the foreground runs the REAL
    /// guard (`RelayCoordinator.adoptGuard`, the exact code `adopt` itself calls) before
    /// acking, then hands the round loop to a detached child via the same hidden
    /// `relay-continue` verb resume uses — carrying the one-time `adoptionNote` forward
    /// explicitly (base64) since, unlike `founderNote`, it is never persisted onto
    /// `RelayState` (see `adopt`'s doc comment).
    private static func runAdoptNoWait(
        relayId: String, pmWorkerId: String, config: RelayCoordinator.Config,
        opts: Options, runtime: ToolRuntime
    ) async {
        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        // RSC-S03 hardening: same one-time dispatch token as resume's --no-wait.
        switch coordinator.adoptGuard(relayId: relayId, pmWorkerId: pmWorkerId, config: config, mintDispatchToken: true) {
        case .failure(let error):
            failAdopt(error)
        case .success(let (flipped, adoptedConfig, note, dispatchToken)):
            guard let dispatchToken else {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "adoptGuard did not mint a dispatch token for a --no-wait continuation")
            }
            var childArgs = [
                "pair", "relay-continue", "--relay", relayId,
                "--max-rounds", String(adoptedConfig.maxRounds),
                "--dispatch-token", dispatchToken,
            ]
            if let rawUntil = opts.value("until") { childArgs += ["--until", rawUntil] }
            childArgs += ["--adoption-note-b64", Data(note.utf8).base64EncodedString()]
            do {
                let process = try DetachedDispatch.launch(cwd: flipped.projectRoot, arguments: childArgs)
                // RSC-S03 hot-fix: same owner-pid handoff as `runResumeNoWait` — see
                // `RelayStateStore.restampOwner`'s doc comment.
                RelayStateStore().restampOwner(id: relayId, pid: process.processIdentifier)
                emitDispatchAck(kind: "relay", id: relayId, pid: process.processIdentifier, json: opts.flag("json"))
            } catch {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not dispatch background relay: \(error)")
            }
        }
    }

    // MARK: - Parsing (throwing, exit-free — unit-testable)

    enum RelayCLIError: Error, Equatable {
        case missingRequired(String)
        case invalidMaxRounds(String)
        case invalidUntil(String)
        case invalidIdleTimeout(String)
        case projectNotFound(String)
        case relayNotFound(String)
        case relayNotEscalated(status: String)
        /// Structured exact-id failure (`--pm-worker` / `--dev-worker`) — carries the
        /// same envelope `AllnighterCLI.failExactId` renders (candidates/suggestions/
        /// nextAction), so the entry point can render it byte-for-byte unchanged
        /// instead of losing that detail through the generic `errorEnvelope` mapping
        /// (mirrors `PilotSeatResolver.Error.exactId`).
        case workerNotAvailable(ExactIdResolver.Failure)
    }

    static func parseStartConfig(
        _ args: [String],
        projectStore: ProjectStore = ProjectStore(),
        models: [Model] = []
    ) throws -> RelayCoordinator.Config {
        let opts = Options(args)
        guard let docPath = opts.value("doc") else { throw RelayCLIError.missingRequired("--doc <path>") }
        guard let projectToken = opts.value("project") else { throw RelayCLIError.missingRequired("--project <id|path>") }
        guard let pmWorkerId = opts.value("pm-worker") else { throw RelayCLIError.missingRequired("--pm-worker <modelId>") }
        guard let devWorkerId = opts.value("dev-worker") else { throw RelayCLIError.missingRequired("--dev-worker <modelId>") }
        // Empty `models` (the default) falls back to the live catalog for real
        // invocations; tests inject a hermetic fixture instead (mirrors PilotCLI's
        // `parseStartConfig(models:)` seam) — never reads live user config in tests.
        let catalogModels = models.isEmpty ? ModelCatalog.resolvedModels(registry: DefaultConfig.registry) : models
        if case .failure(let failure) = ExactIdResolver.resolveWorker(pmWorkerId, flag: "--pm-worker", models: catalogModels) {
            throw RelayCLIError.workerNotAvailable(failure)
        }
        if case .failure(let failure) = ExactIdResolver.resolveWorker(devWorkerId, flag: "--dev-worker", models: catalogModels) {
            throw RelayCLIError.workerNotAvailable(failure)
        }
        guard let project = AllnighterCLI.resolveProject(projectToken, store: projectStore) else {
            throw RelayCLIError.projectNotFound(projectToken)
        }
        guard let maxRounds = parseMaxRounds(opts.value("max-rounds")) else {
            throw RelayCLIError.invalidMaxRounds(opts.value("max-rounds") ?? "")
        }
        let untilParsed = RelayDispatch.parseUntilValidated(opts.value("until"))
        if let bad = untilParsed.invalid { throw RelayCLIError.invalidUntil(bad) }
        // PO-F7: reuses PO-F5's `alln run --idle-timeout` parse helper — no second idle system.
        let idleParsed = RunCLI.parseIdleTimeoutSeconds(opts.value("idle-timeout"))
        if let error = idleParsed.error { throw RelayCLIError.invalidIdleTimeout(error) }
        return RelayCoordinator.Config(
            projectRoot: project.normalizedRootPath,
            projectId: project.id,
            docPath: docPath,
            pmWorkerId: pmWorkerId,
            devWorkerId: devWorkerId,
            maxRounds: maxRounds,
            until: untilParsed.value,
            devTurnIdleTimeoutSeconds: idleParsed.value
        )
    }

    static func parseResumeRequest(
        _ args: [String],
        stateStore: RelayStateStore = RelayStateStore(),
        projectStore: ProjectStore = ProjectStore()
    ) throws -> (relayId: String, answer: String, priorState: RelayState, config: RelayCoordinator.Config) {
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { throw RelayCLIError.missingRequired("--relay <id>") }
        guard let answer = opts.value("answer"), !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayCLIError.missingRequired("--answer <text>")
        }
        guard let priorState = stateStore.load(id: relayId) else { throw RelayCLIError.relayNotFound(relayId) }
        // `priorState` here is the raw persisted read — `RelayCoordinator.resume` (which
        // this request feeds) is what durably reconciles a dead-owner `.running` relay to
        // `.stopped`; this pre-check only needs to know THAT it would be eligible, via the
        // same owner.pid liveness signal, so a founder never sees a stale "not escalated"
        // rejection for a relay that's actually about to reconcile-and-resume (works-test
        // hazard #1: "escalated-only was too narrow").
        let orphaned = priorState.status == .running && stateStore.isOwnerDead(id: relayId)
        guard priorState.isResumable || orphaned else {
            throw RelayCLIError.relayNotEscalated(status: priorState.status.rawValue)
        }
        guard let maxRounds = parseMaxRounds(opts.value("max-rounds")) else {
            throw RelayCLIError.invalidMaxRounds(opts.value("max-rounds") ?? "")
        }
        // The coordinator itself re-derives projectRoot/docPath/pmWorkerId/devWorkerId
        // from the persisted state on resume (RelayCoordinator.resume) — resolving the
        // project here too only recovers a real `projectId` for the RunRequest;
        // `nil` degrades gracefully if the project entry can't be found.
        let untilParsed = RelayDispatch.parseUntilValidated(opts.value("until"))
        if let bad = untilParsed.invalid { throw RelayCLIError.invalidUntil(bad) }
        let projectId = AllnighterCLI.resolveProject(priorState.projectRoot, store: projectStore)?.id
        let config = RelayCoordinator.Config(
            projectRoot: priorState.projectRoot,
            projectId: projectId,
            docPath: priorState.docPath,
            pmWorkerId: priorState.pmWorkerId,
            devWorkerId: priorState.devWorkerId,
            maxRounds: maxRounds,
            until: untilParsed.value
        )
        return (relayId, answer, priorState, config)
    }

    static func parseMaxRounds(_ raw: String?) -> Int? {
        guard let raw else { return 20 }
        guard let value = Int(raw), value > 0 else { return nil }
        return value
    }

    // MARK: - Output

    private static func emit(_ event: RelayCoordinator.RelayEvent, json: Bool) {
        if json {
            print(RelayDispatch.progressJSONLine(event))
        } else {
            print(RelayDispatch.humanProgressLine(event))
        }
    }

    /// RSC-S03: the `--no-wait` dispatch ack, shared by all three verbs — one
    /// `DetachedDispatchJSON` shape, or a human line naming `relay-status` as the way
    /// to attach.
    private static func emitDispatchAck(kind: String, id: String, pid: Int32, json: Bool) {
        if json {
            print(AllnighterCLI.jsonLine(DetachedDispatchJSON(kind: kind, id: id, status: "dispatched", pid: pid)))
        } else {
            print("dispatched (pid \(pid)) — poll with `alln pair relay-status --relay \(id) --json`")
        }
    }

    /// Prints the final `RelayJSON` and exits non-zero for the two "founder must look
    /// at this" endings — `escalated` (a real question) and `stopped` (a ceiling fired,
    /// PM_Relay.md §5 item 3) — so scripting/automation can tell a clean `done` apart
    /// from either. `running` never reaches here: `run`/`resume` only return once the
    /// loop hits a terminal `RelayState`.
    private static func emitTerminal(_ state: RelayState, json: Bool) {
        let relayJSON = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        if json {
            print(AllnighterCLI.jsonLine(relayJSON))
        } else {
            print(RelayDispatch.humanRelaySummary(relayJSON))
        }
        if state.status == .escalated || state.status == .stopped { exit(1) }
    }

    // MARK: - Exit funnel

    private static func fail(_ error: RelayCLIError) -> Never {
        // `.workerNotAvailable` renders through the same `failExactId` funnel the old
        // in-parse `exit()` call used — candidates/suggestions/nextAction included —
        // so real invocations see byte-for-byte the same envelope as before.
        if case .workerNotAvailable(let failure) = error {
            AllnighterCLI.failExactId(failure)
        }
        let (code, message) = errorEnvelope(error)
        AllnighterCLI.fail(code: code, message: message)
    }

    static func errorEnvelope(_ error: RelayCLIError) -> (code: String, message: String) {
        switch error {
        case .workerNotAvailable(let failure):
            return (failure.code, failure.message)
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
        case .relayNotEscalated(let status):
            return ("RELAY_INVALID_STATE", "relay is \(status), not resumable — only an escalated relay, or one reconciled after its owner process died, can be resumed")
        }
    }

    private static func failAdopt(_ error: RelayCoordinator.AdoptError) -> Never {
        let (code, message) = adoptErrorEnvelope(error)
        AllnighterCLI.fail(code: code, message: message)
    }

    static func adoptErrorEnvelope(_ error: RelayCoordinator.AdoptError) -> (code: String, message: String) {
        switch error {
        case .relayNotFound:
            return ("RELAY_NOT_FOUND", "relay not found")
        case .notPilotRelay:
            return ("RELAY_INVALID_STATE", "relay is not a Pilot relay (pmMode != external) — only a Pilot relay can be adopted by a spawned PM")
        case .notAdoptable(let status):
            return ("RELAY_INVALID_STATE", "relay is \(status), not adoptable — only a parked Pilot relay (awaitingPM or escalated) can be adopted")
        case .roundInFlight:
            return ("RELAY_ROUND_IN_FLIGHT", "another process is already dispatching a round for this relay — poll `alln pair relay-status --relay <id> --json` and retry once it settles")
        }
    }

    /// RSC-S01: `RelayCoordinator.resume`'s failure channel. `.relayNotFound`/
    /// `.notResumable` mirror the existing pre-check in `parseResumeRequest` (which
    /// normally catches these first); `.roundInFlight` is new — a concurrent
    /// `resume`/`adopt` already holds this relay's dispatch lock.
    private static func failResume(_ error: RelayCoordinator.DispatchRefusal, relayId: String) -> Never {
        let (code, message) = resumeErrorEnvelope(error, relayId: relayId)
        AllnighterCLI.fail(code: code, message: message)
    }

    static func resumeErrorEnvelope(
        _ error: RelayCoordinator.DispatchRefusal, relayId: String
    ) -> (code: String, message: String) {
        switch error {
        case .relayNotFound:
            return ("RELAY_NOT_FOUND", "relay not found: \(relayId)")
        case .notResumable(let status):
            return ("RELAY_INVALID_STATE", "relay is \(status), not resumable — only an escalated relay, or one reconciled after its owner process died, can be resumed")
        case .roundInFlight:
            return ("RELAY_ROUND_IN_FLIGHT", "another process is already dispatching a round for this relay — poll `alln pair relay-status --relay <id> --json` and retry once it settles")
        case .alreadyActive(let existingRelayId):
            // Unreachable from `resume` — `.alreadyActive` is only ever produced by
            // `RelayCoordinator.run`'s start-time duplicate guard (RSC-S02). Kept for
            // `DispatchRefusal`'s exhaustive switch, not a real resume outcome.
            return ("RELAY_ALREADY_ACTIVE", "a relay is already running for this project + doc: \(existingRelayId)")
        }
    }

    /// RSC-S02: `RelayCoordinator.run`'s failure channel. `.alreadyActive` is the only
    /// case `run` ever actually produces (a live-owner `.running` relay already exists
    /// on this normalized root + doc) — `.relayNotFound`/`.notResumable`/`.roundInFlight`
    /// are unreachable from a fresh start, kept only for `DispatchRefusal`'s exhaustive
    /// switch (they're `resume`/`adopt`'s outcomes, not `run`'s).
    private static func failStart(_ error: RelayCoordinator.DispatchRefusal) -> Never {
        let (code, message) = startErrorEnvelope(error)
        AllnighterCLI.fail(code: code, message: message)
    }

    static func startErrorEnvelope(
        _ error: RelayCoordinator.DispatchRefusal
    ) -> (code: String, message: String) {
        switch error {
        case .alreadyActive(let existingRelayId):
            return (
                "RELAY_ALREADY_ACTIVE",
                "a relay is already running for this project + doc: \(existingRelayId) — read it with `alln pair relay-status --relay \(existingRelayId) --json`, resume or adopt it, or wait; do not start a second relay on the same doc"
            )
        case .relayNotFound, .notResumable, .roundInFlight:
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "unexpected DispatchRefusal from RelayCoordinator.run: \(error)")
        }
    }

    private static func usage(_ detail: String) -> Never {
        FileHandle.standardError.write(Data("usage: alln pair \(detail)\n".utf8))
        exit(2)
    }
}
