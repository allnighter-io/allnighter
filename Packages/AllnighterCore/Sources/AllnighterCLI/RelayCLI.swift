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
        guard !args.isEmpty else { usage("relay --doc <path> --project <id|path> --pm-model <modelId> --dev-model <modelId> [--until HH:MM] [--max-rounds N] [--idle-timeout <seconds>] [--no-wait] [--json]") }
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

    /// RSC-HF: `pair relay --no-wait`. Non-mutating preflight fails loud and spawns
    /// nothing. On success, spawn the same registered `pair relay` verb (no hidden
    /// continuation) and ack only after the child durably claims via `DetachedHandoff`.
    private static func runRelayNoWait(config: RelayCoordinator.Config, opts: Options) async {
        let stateStore = RelayStateStore()
        if case .failure(let refusal) = RelayCoordinator.preflightStart(
            projectRoot: config.projectRoot, docPath: config.docPath, stateStore: stateStore
        ) {
            failStart(refusal)
        }
        await awaitDetachedAcceptance(cwd: config.projectRoot, json: opts.flag("json"))
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

    /// RSC-HF: `pair relay-resume --no-wait`. Parent does not mutate — the child runs
    /// the normal registered `relay-resume` path (one guarded entry point) and reports
    /// acceptance via `DetachedHandoff` after the durable `.running` claim.
    private static func runResumeNoWait(
        relayId: String, founderAnswer: String, config: RelayCoordinator.Config,
        opts: Options, runtime: ToolRuntime
    ) async {
        _ = (relayId, founderAnswer, runtime) // parsed/validated above; child re-runs the real path
        await awaitDetachedAcceptance(cwd: config.projectRoot, json: opts.flag("json"))
    }

    /// `pair relay adopt --relay <id> --pm-model <id>` (docs/phases/Pilot_Relay.md
    /// §5, PL-S06) — adopt (unattended handover): hands a parked Pilot relay to a
    /// spawned PM, then lets the loop run to a terminal state exactly like `relay`/
    /// `relay-resume`. `projectRoot`/`docPath`/`devModelId` are always read from the
    /// loaded relay (never from a flag here) — an adopt can never silently redirect a
    /// relay at a different doc or repo, same discipline `resume` already follows.
    static func runAdopt(_ args: [String], runtime: ToolRuntime) async {
        guard !args.isEmpty else { usage("relay adopt --relay <id> --pm-model <modelId> [--max-rounds N] [--until HH:MM] [--no-wait] [--json]") }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        guard let pmModelId = opts.value("pm-model") else { fail(.missingRequired("--pm-model <modelId>")) }
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
            pmModelId: pmModelId, devModelId: priorState.devModelId,
            maxRounds: maxRounds, until: untilParsed.value
        )

        if opts.flag("no-wait") {
            await runAdoptNoWait(relayId: relayId, pmModelId: pmModelId, config: config, opts: opts, runtime: runtime)
            return
        }

        // URN-S02: guarantee a live notifier before dispatching a real dev turn.
        // Reachable both directly (`pair relay adopt`) and via `runRelay`'s
        // early redirect — this is the only place the check runs for adopt.
        ServeAutoLaunchCLI.reportToStderr(ServeAutoLaunchCLI.ensureRunning(opts))

        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        let emitJSON = opts.flag("json")
        let result = await coordinator.adopt(relayId: relayId, pmModelId: pmModelId, config: config) { event in
            emit(event, json: emitJSON)
        }
        switch result {
        case .success(let state):
            emitTerminal(state, json: emitJSON)
        case .failure(let error):
            failAdopt(error)
        }
    }

    /// RSC-HF: `pair relay adopt --no-wait`. Parent does not mutate — child runs the
    /// normal registered `relay adopt` path and reports acceptance after claim.
    private static func runAdoptNoWait(
        relayId: String, pmModelId: String, config: RelayCoordinator.Config,
        opts: Options, runtime: ToolRuntime
    ) async {
        _ = (relayId, pmModelId, runtime)
        await awaitDetachedAcceptance(cwd: config.projectRoot, json: opts.flag("json"))
    }

    /// Shared `--no-wait` accept wait: spawn same argv minus `--no-wait`, ack only after
    /// the child writes `DetachedHandoff` accepted/refused.
    private static func awaitDetachedAcceptance(cwd: String, json: Bool) async {
        do {
            switch try DetachedDispatch.launchAndAwaitAcceptance(cwd: cwd, arguments: DetachedDispatch.childArguments()) {
            case .accepted(let id, let pid):
                emitDispatchAck(kind: "relay", id: id, pid: pid, json: json)
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

    // MARK: - Parsing (throwing, exit-free — unit-testable)

    enum RelayCLIError: Error, Equatable {
        case missingRequired(String)
        case invalidMaxRounds(String)
        case invalidUntil(String)
        case invalidIdleTimeout(String)
        case projectNotFound(String)
        case relayNotFound(String)
        case relayNotEscalated(status: String)
        /// Structured exact-id failure (`--pm-model` / `--dev-model`) — carries the
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
        guard let pmModelId = opts.value("pm-model") else { throw RelayCLIError.missingRequired("--pm-model <modelId>") }
        guard let devModelId = opts.value("dev-model") else { throw RelayCLIError.missingRequired("--dev-model <modelId>") }
        // Empty `models` (the default) falls back to the live catalog for real
        // invocations; tests inject a hermetic fixture instead (mirrors PilotCLI's
        // `parseStartConfig(models:)` seam) — never reads live user config in tests.
        let catalogModels = models.isEmpty ? ModelCatalog.resolvedModels(registry: DefaultConfig.registry) : models
        if case .failure(let failure) = ExactIdResolver.resolveWorker(pmModelId, flag: "--pm-model", models: catalogModels) {
            throw RelayCLIError.workerNotAvailable(failure)
        }
        if case .failure(let failure) = ExactIdResolver.resolveWorker(devModelId, flag: "--dev-model", models: catalogModels) {
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
            pmModelId: pmModelId,
            devModelId: devModelId,
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
        // The coordinator itself re-derives projectRoot/docPath/pmModelId/devModelId
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
            pmModelId: priorState.pmModelId,
            devModelId: priorState.devModelId,
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
            DetachedHandoff.reportRefused(code: failure.code, message: failure.message)
            AllnighterCLI.failExactId(failure)
        }
        let (code, message) = errorEnvelope(error)
        DetachedHandoff.reportRefused(code: code, message: message)
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
        DetachedHandoff.reportRefused(code: code, message: message)
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
        case .journalUnavailable:
            return ("RELAY_JOURNAL_UNAVAILABLE", "could not persist relay claim — journal write failed")
        }
    }

    /// RSC-S01: `RelayCoordinator.resume`'s failure channel. `.relayNotFound`/
    /// `.notResumable` mirror the existing pre-check in `parseResumeRequest` (which
    /// normally catches these first); `.roundInFlight` is new — a concurrent
    /// `resume`/`adopt` already holds this relay's dispatch lock.
    private static func failResume(_ error: RelayCoordinator.DispatchRefusal, relayId: String) -> Never {
        let (code, message) = resumeErrorEnvelope(error, relayId: relayId)
        DetachedHandoff.reportRefused(id: relayId, code: code, message: message)
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
        case .journalUnavailable:
            return ("RELAY_JOURNAL_UNAVAILABLE", "could not persist relay claim — journal write failed")
        }
    }

    /// RSC-S02: `RelayCoordinator.run`'s failure channel. `.alreadyActive` is the only
    /// case `run` ever actually produces (a live-owner `.running` relay already exists
    /// on this normalized root + doc) — `.relayNotFound`/`.notResumable`/`.roundInFlight`
    /// are unreachable from a fresh start, kept only for `DispatchRefusal`'s exhaustive
    /// switch (they're `resume`/`adopt`'s outcomes, not `run`'s).
    private static func failStart(_ error: RelayCoordinator.DispatchRefusal) -> Never {
        let (code, message) = startErrorEnvelope(error)
        DetachedHandoff.reportRefused(code: code, message: message)
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
        case .journalUnavailable:
            return ("RELAY_JOURNAL_UNAVAILABLE", "could not persist relay claim — journal write failed")
        }
    }

    private static func usage(_ detail: String) -> Never {
        FileHandle.standardError.write(Data("usage: alln pair \(detail)\n".utf8))
        exit(2)
    }
}
