import Foundation
import AllnighterCore
import AllnighterEngine

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
    static func run(_ args: [String], runtime: ToolRuntime) async {
        guard let sub = args.first else { usage() }
        switch sub {
        case "start": await runStart(Array(args.dropFirst()), runtime: runtime)
        case "handoff": await runHandoff(Array(args.dropFirst()), runtime: runtime)
        case "status": runStatus(Array(args.dropFirst()))
        case "watch": runWatch(Array(args.dropFirst()))
        case "adopt": runAdopt(Array(args.dropFirst()))
        default: usage()
        }
    }

    // MARK: - start

    static func runStart(_ args: [String], runtime: ToolRuntime) async {
        guard !args.isEmpty else { usage("pilot start --doc <path> --project <id|path> --dev-worker <modelId> [--max-rounds N] [--json]") }
        let config: RelayCoordinator.Config
        do {
            config = try parseStartConfig(args)
        } catch let error as PilotCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        switch coordinator.startPilot(config: config) {
        case .success(let state):
            emitState(state, json: Options(args).flag("json"))
        case .failure(.untilNotSupported):
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "--until is not supported for pilot start — Pilot has no clock; each round advances only when you call `pilot handoff`."
            )
        }
    }

    static func parseStartConfig(_ args: [String], projectStore: ProjectStore = ProjectStore()) throws -> RelayCoordinator.Config {
        let opts = Options(args)
        guard let docPath = opts.value("doc") else { throw PilotCLIError.missingRequired("--doc <path>") }
        guard let projectToken = opts.value("project") else { throw PilotCLIError.missingRequired("--project <id|path>") }
        guard let devWorkerId = opts.value("dev-worker") else { throw PilotCLIError.missingRequired("--dev-worker <modelId>") }
        guard let project = AllnighterCLI.resolveProject(projectToken, store: projectStore) else {
            throw PilotCLIError.projectNotFound(projectToken)
        }
        guard let maxRounds = RelayCLI.parseMaxRounds(opts.value("max-rounds")) else {
            throw PilotCLIError.invalidMaxRounds(opts.value("max-rounds") ?? "")
        }
        return RelayCoordinator.Config(
            projectRoot: project.normalizedRootPath,
            projectId: project.id,
            docPath: docPath,
            // No PM model dispatches in Pilot — the sentinel documents that, RunService
            // never resolves it.
            pmWorkerId: RelayState.externalPMWorkerId,
            devWorkerId: devWorkerId,
            maxRounds: maxRounds
            // `until` deliberately never wired from a flag here — Pilot exposes no
            // `--until`, so `RelayCoordinator.startPilot`'s guard never fires from this
            // path; it exists as the coordinator's own defense in depth.
        )
    }

    // MARK: - handoff

    static func runHandoff(_ args: [String], runtime: ToolRuntime) async {
        guard !args.isEmpty else { usage("pilot handoff --relay <id> (--file <md> | stdin) [--no-wait] [--json]") }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        let submission: String
        do {
            submission = try readSubmission(opts)
        } catch let error as PilotCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        if opts.flag("no-wait") {
            dispatchHandoffInBackground(relayId: relayId, submission: submission, jsonRequested: opts.flag("json"))
            return
        }

        let stateStore = RelayStateStore()
        guard stateStore.load(id: relayId) != nil else { fail(.relayNotFound(relayId)) }
        let projectId = AllnighterCLI.resolveProject(loadedProjectRoot(relayId, stateStore: stateStore) ?? "", store: ProjectStore())?.id

        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        let result = await coordinator.runExternalRound(relayId: relayId, submission: submission, projectId: projectId)
        switch result {
        case .success(let payload):
            emitHandoffResult(payload, json: opts.flag("json"))
        case .failure(let error):
            failPilotRound(error)
        }
    }

    /// Reads the round's markdown from `--file`, or stdin when omitted (the doc's
    /// `(--file <md> | stdin)`).
    static func readSubmission(_ opts: Options) throws -> String {
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

    private static func loadedProjectRoot(_ relayId: String, stateStore: RelayStateStore) -> String? {
        stateStore.load(id: relayId)?.projectRoot
    }

    /// `--no-wait`: re-invokes THIS SAME executable as a detached background process
    /// running the normal (blocking) `pilot handoff` against a staged copy of the
    /// submission — one dispatch path, no second in-process implementation to drift
    /// from the default. The foreground call returns as soon as the child is launched;
    /// the caller polls with `pilot status`/`pilot watch`.
    private static func dispatchHandoffInBackground(relayId: String, submission: String, jsonRequested: Bool) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-pilot-handoff-\(relayId)-\(UUID().uuidString).md")
        do {
            try submission.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not stage handoff submission: \(error)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        var childArgs = ["pair", "pilot", "handoff", "--relay", relayId, "--file", tempURL.path]
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
        print("dispatched (pid \(process.processIdentifier)) — poll with `alln pair pilot status --relay \(relayId) --json` or `alln pair pilot watch --relay \(relayId)`")
    }

    private static func emitHandoffResult(_ payload: RelayCoordinator.PilotRoundResult, json: Bool) {
        let relayJSON = RelayJSON.project(payload.state, contractVersion: ContractRegistry.contractVersion)
        if json {
            print(AllnighterCLI.jsonString(PilotHandoffJSON(relay: relayJSON, devReport: payload.devReport)))
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

    static func runStatus(
        _ args: [String],
        stateStore: RelayStateStore = RelayStateStore(),
        threadProjector: RelayThreadProjector? = RelayThreadProjector()
    ) {
        guard !args.isEmpty else { usage("pilot status --relay <id> [--json]") }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        guard let loaded = stateStore.load(id: relayId) else { fail(.relayNotFound(relayId)) }
        let state = RelayCoordinator.reconcileOrphan(loaded, stateStore: stateStore, threadProjector: threadProjector, now: Date.init)
        emitState(state, json: opts.flag("json"))
    }

    // MARK: - watch

    /// Polls until the in-flight round settles (`status != .running`) — `.running` only
    /// ever happens transiently, while a `pilot handoff` dev turn is dispatching.
    static func runWatch(
        _ args: [String],
        stateStore: RelayStateStore = RelayStateStore(),
        threadProjector: RelayThreadProjector? = RelayThreadProjector(),
        pollInterval: TimeInterval = 1.0,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        guard !args.isEmpty else { usage("pilot watch --relay <id> [--json]") }
        let opts = Options(args)
        guard let relayId = opts.value("relay") else { fail(.missingRequired("--relay <id>")) }
        guard var state = stateStore.load(id: relayId) else { fail(.relayNotFound(relayId)) }
        state = RelayCoordinator.reconcileOrphan(state, stateStore: stateStore, threadProjector: threadProjector, now: Date.init)
        while state.status == .running {
            sleep(pollInterval)
            guard let reloaded = stateStore.load(id: relayId) else { fail(.relayNotFound(relayId)) }
            state = RelayCoordinator.reconcileOrphan(reloaded, stateStore: stateStore, threadProjector: threadProjector, now: Date.init)
        }
        emitState(state, json: opts.flag("json"))
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

    /// The next-action discipline (Pilot_Relay.md §1 decision 5): every non-JSON print
    /// says, in one line, what the piloting session should do next.
    static func nextActionLine(for state: RelayState) -> String {
        switch state.status {
        case .awaitingPM:
            return "next: write this round's review + RelayVerdict tail, then `alln pair pilot handoff --relay \(state.id) --file <md>` (or pipe markdown via stdin)."
        case .running:
            return "a round is in flight — poll with `alln pair pilot status --relay \(state.id) --json` or `alln pair pilot watch --relay \(state.id)`."
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
        case projectNotFound(String)
        case relayNotFound(String)
        case noSubmission
        case fileUnreadable(String)
    }

    static func errorEnvelope(_ error: PilotCLIError) -> (code: String, message: String) {
        switch error {
        case .missingRequired(let flag):
            return ("CLI_USAGE_ERROR", "\(flag) required")
        case .invalidMaxRounds(let raw):
            return ("CLI_USAGE_ERROR", "--max-rounds must be a positive integer, got '\(raw)'")
        case .projectNotFound(let token):
            return ("PROJECT_NOT_FOUND", "project not found: \(token)")
        case .relayNotFound(let id):
            return ("RELAY_NOT_FOUND", "relay not found: \(id)")
        case .noSubmission:
            return ("CLI_USAGE_ERROR", "no submission text — pass --file <md> or pipe markdown via stdin")
        case .fileUnreadable(let path):
            return ("CLI_USAGE_ERROR", "could not read submission file: \(path)")
        }
    }

    static func pilotRoundErrorEnvelope(_ error: RelayCoordinator.PilotRoundError) -> (code: String, message: String) {
        switch error {
        case .relayNotFound:
            return ("RELAY_NOT_FOUND", "relay not found")
        case .notPilotRelay:
            return ("RELAY_INVALID_STATE", "relay is not a Pilot relay (pmMode != external) — use `alln pair relay`/`alln pair relay-resume` instead")
        case .roundInFlight:
            return ("RELAY_ROUND_IN_FLIGHT", "a round is already dispatching for this relay — wait for it to settle, or poll with `pilot status`/`pilot watch`")
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

    private static func usage(_ detail: String = "pilot start|handoff|status|watch|adopt") -> Never {
        FileHandle.standardError.write(Data("usage: alln pair \(detail)\n".utf8))
        exit(2)
    }
}

/// `pilot handoff --json` envelope: the same `RelayJSON` every other relay verb emits,
/// plus the dev's report verbatim when a dev turn delivered in THIS call (nil for a
/// done/escalate/ceiling/stagnation round, or when the dev turn never delivered).
struct PilotHandoffJSON: Encodable {
    let relay: RelayJSON
    let devReport: String?
}
