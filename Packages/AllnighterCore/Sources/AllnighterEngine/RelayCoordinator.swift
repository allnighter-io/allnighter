import Foundation
import AllnighterCore

/// PM Relay control plane (docs/phases/PM_Relay.md §2) — the turn-based, unattended
/// PM↔dev loop that replaces the founder's copy-paste relay. Mirrors `PairCoordinator`'s
/// shape: a plain `Sendable` struct whose async methods drive the actor-isolated
/// `RunService`; no isolation of its own is needed because every mutating step already
/// runs sequentially through `RunService`'s write lock, and the one-mutating-worker
/// invariant holds by construction (turns never overlap).
///
/// Every turn — PM or dev — dispatches through the SAME `RunService.run` path used by
/// ordinary chat/execution, under `execution_playbook` (a single mutating worker), with
/// `workerId` pinned to the relay's PM or dev seat. Allnighter never invents a second
/// dispatch route (PM_Relay.md §5 item 2).
public struct RelayCoordinator: Sendable {
    public struct Config: Sendable {
        public var projectRoot: String
        public var projectId: String?
        /// Repo-relative path to the spec doc — never a payload; the PM re-reads it fresh
        /// from disk each round (PM_Relay.md §2, "the doc is an anchor, not a payload").
        public var docPath: String
        public var pmWorkerId: String
        public var devWorkerId: String
        public var maxRounds: Int
        public var until: Date?
        /// Consecutive rounds with zero repo change AND verdict `continue` before the
        /// relay stops itself as a probable PM↔dev deadlock. Approximates the doc's
        /// `--max-consecutive-flags` (§5 item 3) — see `RelayCoordinator.loop`.
        public var stagnationRoundCap: Int
        /// The single-mutating-worker team both seats run under. Defaults to
        /// `execution_playbook` (`PairCoordinator.Seats` uses the same team for its
        /// executor seat).
        public var presetId: String

        public init(
            projectRoot: String,
            projectId: String? = nil,
            docPath: String,
            pmWorkerId: String,
            devWorkerId: String,
            maxRounds: Int = 20,
            until: Date? = nil,
            stagnationRoundCap: Int = 3,
            presetId: String = "execution_playbook"
        ) {
            self.projectRoot = projectRoot
            self.projectId = projectId
            self.docPath = docPath
            self.pmWorkerId = pmWorkerId
            self.devWorkerId = devWorkerId
            self.maxRounds = max(1, maxRounds)
            self.until = until
            self.stagnationRoundCap = max(1, stagnationRoundCap)
            self.presetId = presetId
        }
    }

    /// Transport-agnostic progress events (PM_Relay.md §6 R-S04: "keep transport-agnostic
    /// here"). R-S05's CLI maps these to NDJSON; a GUI or MCP progress stream could map
    /// them to anything else — this type carries no opinion about presentation.
    public enum RelayEvent: Sendable, Equatable {
        case roundStarted(round: Int)
        case pmTurnFinished(round: Int, verdict: RelayVerdict.Verdict)
        case gateBlocked(round: Int, dangerClass: String, reason: String)
        case devTurnFinished(round: Int)
        case escalated(note: String)
        case done(note: String?)
        case stopped(reason: String)
    }

    public typealias EventSink = @Sendable (RelayEvent) -> Void

    // MARK: - Pilot types (docs/phases/Pilot_Relay.md)

    /// `startPilot` failure. A usage error, not a domain state — Pilot has no clock,
    /// so a non-nil `Config.until` is refused rather than silently ignored.
    public enum PilotStartError: Swift.Error, Sendable, Equatable {
        case untilNotSupported
    }

    /// `runExternalRound` failure. Every case except `.relayNotFound`/`.notPilotRelay`
    /// leaves the relay's durable state exactly as it was before the call — a pilot
    /// round only ever lands on the ledger once it actually starts (verdict parsed,
    /// and, for `continue`, the handover cleared `HandoverGate`).
    public enum PilotRoundError: Swift.Error, Sendable, Equatable {
        case relayNotFound
        /// The relay exists but isn't a pilot relay (`pmMode != .external`) — use
        /// `pair relay`/`pair relay-resume` for a spawned relay instead.
        case notPilotRelay
        /// A round is already dispatching (durable check: `status == .running`) —
        /// one mutating dev turn at a time, unchanged law.
        case roundInFlight
        /// The relay is in some OTHER non-`awaitingPM` status (`done`/`escalated`/
        /// `stopped`) — there's nothing to hand off to.
        case notAwaitingPM(status: String)
        /// `submission`'s tail didn't parse as a `RelayVerdict`. No re-ask machinery
        /// in Pilot — the piloting session is live and just resubmits.
        case verdictUnparseable(RelayVerdictParser.ExtractError)
        /// `HandoverGate` blocked the `continue` verdict's handover before it ever
        /// reached the dev seat. Pilot never escalates on a gate block (unlike a
        /// spawned relay) — the piloting session is right there to rephrase.
        case handoverBlocked(dangerClass: String, code: String, reason: String, snippet: String)
    }

    /// `runExternalRound`'s success payload: the updated `RelayState` plus, when a dev
    /// turn actually dispatched and delivered this call, its report text verbatim —
    /// so the CLI can print it without a second `RunStore` lookup keyed off
    /// `state.rounds.last?.devRunId` (`docs/phases/Pilot_Relay.md` §2 "read dev report
    /// ← report + round log returned in the same call").
    public struct PilotRoundResult: Sendable, Equatable {
        public var state: RelayState
        public var devReport: String?

        public init(state: RelayState, devReport: String? = nil) {
            self.state = state
            self.devReport = devReport
        }
    }

    private let runService: RunService
    private let gitObserver: GitObserver
    private let stateStore: RelayStateStore
    private let runStore: RunStore
    /// Optional (PM_Relay.md §6 R-S07): projects the relay onto a `WorkThread` so the
    /// Mac inbox shows the loop live. Pure composition — `nil` by default so every
    /// existing test/headless caller keeps working unchanged; CLI/MCP construct one via
    /// `RelayDispatch.makeCoordinator` so real relays always show in the inbox.
    private let threadProjector: RelayThreadProjector?
    private let now: @Sendable () -> Date
    private let idFactory: @Sendable () -> String

    public init(
        runService: RunService,
        gitObserver: GitObserver = GitObserver(),
        stateStore: RelayStateStore = RelayStateStore(),
        runStore: RunStore = RunStore(),
        threadProjector: RelayThreadProjector? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        idFactory: @escaping @Sendable () -> String = { "relay_\(UUID().uuidString.lowercased())" }
    ) {
        self.runService = runService
        self.gitObserver = gitObserver
        self.stateStore = stateStore
        self.runStore = runStore
        self.threadProjector = threadProjector
        self.now = now
        self.idFactory = idFactory
    }

    // MARK: - Entry points

    /// Starts a new relay and runs it to a terminal `RelayState` (`done`, `escalated`, or
    /// `stopped`). Every round is persisted the moment it changes (durable mid-round).
    public func run(config: Config, events: EventSink? = nil) async -> RelayState {
        var state = RelayState(
            id: idFactory(),
            projectRoot: config.projectRoot,
            docPath: config.docPath,
            pmWorkerId: config.pmWorkerId,
            devWorkerId: config.devWorkerId,
            status: .running,
            createdAt: now()
        )
        threadProjector?.started(state: state, projectId: config.projectId)
        persist(state)
        await loop(state: &state, config: config, events: events)
        return state
    }

    // MARK: - Pilot (docs/phases/Pilot_Relay.md) — `pmMode: .external`

    /// `pilot start` — creates a parked, PM-less relay: `pmMode: .external`,
    /// `status: .awaitingPM`, zero rounds. Pilot has no clock (`until` is meaningless
    /// without a process advancing the loop between rounds), so a non-nil
    /// `config.until` is a usage error rather than silently ignored — the founder
    /// should learn immediately that `--until` doesn't apply here, not have it
    /// quietly do nothing. `config.maxRounds`/`config.stagnationRoundCap` are captured
    /// onto the durable state (`RelayState.pilotMaxRounds`/`pilotStagnationRoundCap`)
    /// because, unlike a spawned relay's `run`/`resume`, there is no long-lived process
    /// to re-supply them at every later round — each `pilot handoff` is a fresh CLI
    /// invocation. `config.pmWorkerId` is ignored; the durable `pmWorkerId` is always
    /// `RelayState.externalPMWorkerId` (there is no PM model to dispatch).
    public func startPilot(config: Config) -> Result<RelayState, PilotStartError> {
        guard config.until == nil else { return .failure(.untilNotSupported) }
        let state = RelayState(
            id: idFactory(),
            projectRoot: config.projectRoot,
            docPath: config.docPath,
            pmWorkerId: RelayState.externalPMWorkerId,
            devWorkerId: config.devWorkerId,
            status: .awaitingPM,
            pmMode: .external,
            createdAt: now(),
            pilotMaxRounds: config.maxRounds,
            pilotStagnationRoundCap: config.stagnationRoundCap
        )
        threadProjector?.started(state: state, projectId: config.projectId)
        persist(state)
        return .success(state)
    }

    /// `pilot handoff` — runs exactly ONE external round: the piloting session's raw
    /// markdown `submission` stands in for a spawned PM turn. Reuses the shipped round
    /// machinery end to end (`RelayVerdictParser`, `HandoverGate`, `RelayDevPrompt`,
    /// `dispatchTurn`'s classifier/retries) — Pilot never invents a second dispatch
    /// path (Pilot_Relay.md §1 decision 1).
    ///
    /// Durability doubles as mutual exclusion: `awaitingPM` is the only status this
    /// accepts a round from, and the very first thing a successful call does is flip
    /// the persisted status to `.running` BEFORE the (possibly long) dev dispatch —
    /// so a second `pilot handoff` racing against this one sees `.running` on disk
    /// and refuses with `.roundInFlight`, exactly the durable check the doc calls for.
    ///
    /// A parse failure or a gate block leaves NO round on the ledger and the relay
    /// stays `awaitingPM` untouched — there is no re-ask machinery here (unlike the
    /// spawned PM's one-re-ask-then-escalate ladder): the piloting session is a live
    /// human/agent right there to fix its own submission and call `handoff` again.
    /// `done`/`escalate` verdicts DO record a round (the submission is this round's
    /// entire run-truth, not a payload to discard) and settle the relay exactly like
    /// a spawned round would.
    public func runExternalRound(
        relayId: String, submission: String, projectId: String? = nil, events: EventSink? = nil
    ) async -> Result<PilotRoundResult, PilotRoundError> {
        guard var state = stateStore.load(id: relayId) else { return .failure(.relayNotFound) }
        guard state.pmMode == .external else { return .failure(.notPilotRelay) }
        if state.status == .running { return .failure(.roundInFlight) }
        guard state.status == .awaitingPM else { return .failure(.notAwaitingPM(status: state.status.rawValue)) }

        let roundNumber = state.rounds.count + 1
        let maxRounds = state.pilotMaxRounds ?? 20
        if roundNumber > maxRounds {
            stop(&state, reason: "reached --max-rounds (\(maxRounds))")
            events?(.stopped(reason: state.stoppedReason ?? ""))
            return .success(PilotRoundResult(state: state, devReport: nil))
        }
        let stagnationCap = state.pilotStagnationRoundCap ?? 3
        if trailingStagnationStreak(state.rounds) >= stagnationCap {
            stop(&state, reason: "stagnation: \(stagnationCap) consecutive rounds with no repo change and verdict continue — likely PM↔dev deadlock")
            events?(.stopped(reason: state.stoppedReason ?? ""))
            return .success(PilotRoundResult(state: state, devReport: nil))
        }

        let extraction: RelayVerdictParser.Extraction
        switch RelayVerdictParser.extract(from: submission) {
        case .success(let ex): extraction = ex
        case .failure(let parseError): return .failure(.verdictUnparseable(parseError))
        }
        events?(.pmTurnFinished(round: roundNumber, verdict: extraction.verdict.verdict))

        switch extraction.verdict.verdict {
        case .done:
            state.rounds.append(RelayRound(
                roundNumber: roundNumber, baselineHead: gitObserver.observe(rootPath: state.projectRoot).head,
                verdict: extraction.verdict, startedAt: now(), finishedAt: now(), outcome: .done,
                externalSubmission: submission
            ))
            finish(&state, note: extraction.verdict.note)
            events?(.done(note: state.note))
            return .success(PilotRoundResult(state: state, devReport: nil))

        case .escalate:
            state.rounds.append(RelayRound(
                roundNumber: roundNumber, baselineHead: gitObserver.observe(rootPath: state.projectRoot).head,
                verdict: extraction.verdict, startedAt: now(), finishedAt: now(), outcome: .escalated,
                externalSubmission: submission
            ))
            let note = extraction.verdict.note ?? "PM escalated with no note (round \(roundNumber))"
            escalate(&state, note: note)
            events?(.escalated(note: state.note ?? ""))
            return .success(PilotRoundResult(state: state, devReport: nil))

        case .continueRelay:
            guard let handover = extraction.verdict.handover, !handover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                // Unreachable in practice — `RelayVerdictParser` already guarantees a
                // non-empty handover for `continue` — kept as a defensive mirror of
                // the spawned loop's equivalent guard.
                return .failure(.verdictUnparseable(.continueWithoutHandover))
            }

            let gateDecision = HandoverGate.evaluate(handoverText: handover)
            if case .blocked(let dangerClass, let code, let reason, let snippet) = gateDecision {
                events?(.gateBlocked(round: roundNumber, dangerClass: dangerClass.rawValue, reason: reason))
                return .failure(.handoverBlocked(dangerClass: dangerClass.rawValue, code: code, reason: reason, snippet: snippet))
            }

            events?(.roundStarted(round: roundNumber))
            var round = RelayRound(
                roundNumber: roundNumber,
                baselineHead: gitObserver.observe(rootPath: state.projectRoot).head,
                verdict: extraction.verdict,
                gate: RelayGateSummary(decision: gateDecision),
                startedAt: now(),
                externalSubmission: submission,
                dirtyFiles: gitObserver.dirtyFiles(rootPath: state.projectRoot)
            )
            state.rounds.append(round)
            // The durable in-flight marker: a concurrent `pilot handoff` racing this
            // one now sees `.running` on disk and refuses (`.roundInFlight`) instead
            // of dispatching a second dev turn on the same repo root.
            state.status = .running
            persist(state)

            let devDisplayName = await runService.workerDisplayName(forModelId: state.devWorkerId)
            let devRequest = RunRequest(
                message: RelayDevPrompt.assemble(context: .init(
                    handover: handover, docPath: state.docPath, roundNumber: roundNumber,
                    workerDisplayName: devDisplayName)),
                repoRoot: state.projectRoot, projectId: projectId,
                presetId: "execution_playbook", workerId: state.devWorkerId
            )
            // No `--until` in Pilot — `dispatchTurn` only needs `config` for its
            // deadline plumbing, which is always inert here (`until: nil`).
            let dispatchConfig = Config(
                projectRoot: state.projectRoot, projectId: projectId, docPath: state.docPath,
                pmWorkerId: state.pmWorkerId, devWorkerId: state.devWorkerId,
                maxRounds: maxRounds, until: nil, stagnationRoundCap: stagnationCap
            )
            let devDispatch = await dispatchTurn(devRequest, config: dispatchConfig)

            switch devDispatch {
            case .deadline:
                // Unreachable — Pilot never sets `until` — kept only so this switch
                // stays exhaustive against `TurnDispatch`.
                round.outcome = .stopped
                round.finishedAt = now()
                state.rounds[state.rounds.count - 1] = round
                stop(&state, reason: "--until deadline reached during the dev turn (round \(roundNumber))")
                events?(.stopped(reason: state.stoppedReason ?? ""))
                return .success(PilotRoundResult(state: state, devReport: nil))
            case .serviceError(let error):
                round.outcome = .escalated
                round.finishedAt = now()
                state.rounds[state.rounds.count - 1] = round
                escalate(&state, note: "dev turn failed to dispatch: \(error.description)")
                events?(.escalated(note: state.note ?? ""))
                return .success(PilotRoundResult(state: state, devReport: nil))
            case .budgetExhausted(let reason):
                round.outcome = .escalated
                round.finishedAt = now()
                state.rounds[state.rounds.count - 1] = round
                escalate(&state, note: "dev turn \(reason) (round \(roundNumber))")
                events?(.escalated(note: state.note ?? ""))
                return .success(PilotRoundResult(state: state, devReport: nil))
            case .delivered(let devRun, let devOutput):
                round.devRunId = devRun.id
                round.headAfterDev = gitObserver.observe(rootPath: state.projectRoot).head
                round.outcome = .continued
                round.finishedAt = now()
                state.rounds[state.rounds.count - 1] = round
                // Back to parked — the piloting session reviews the dev report and
                // calls `pilot handoff` again when ready. No clock, no auto-advance.
                state.status = .awaitingPM
                persist(state)
                events?(.devTurnFinished(round: roundNumber))
                return .success(PilotRoundResult(state: state, devReport: devOutput))
            }
        }
    }

    // MARK: - Adopt (docs/phases/Pilot_Relay.md §5, PL-S06) — the night-shift handover

    /// `alln pair relay adopt` failure. Every case leaves the relay's durable state
    /// exactly as it was before the call.
    public enum AdoptError: Swift.Error, Sendable, Equatable {
        case relayNotFound
        /// The relay isn't a Pilot relay (`pmMode != .external`) — nothing to adopt
        /// FROM (use `resume` for a spawned relay instead).
        case notPilotRelay
        /// Anything other than a parked pilot relay (`awaitingPM` or `escalated`): a
        /// round in flight (`running`), a finished relay (`done`), or a ceiling-fired
        /// one (`stopped`). Only a genuinely parked relay can be handed to a spawned PM.
        case notAdoptable(status: String)
    }

    /// `alln pair relay adopt --relay <id> --pm-worker <id>` (`docs/phases/
    /// Pilot_Relay.md` §5 "the night-shift handover is the strategic unlock") —
    /// converts a PARKED pilot relay (`pmMode == .external`, `status == .awaitingPM`
    /// or `.escalated`) to `pmMode: .spawned` with `pmWorkerId` as the new PM seat,
    /// then CONTINUES the SAME relay — same id, same round log, same thread — from
    /// exactly where the piloting session left it.
    ///
    /// Round-N context threading needs no new machinery: `runRound`'s existing
    /// `previousRound` lookup (`state.rounds[state.rounds.count - 2]`) reads the last
    /// round's `baselineHead`/`headAfterDev`/`devRunId` regardless of whether that
    /// round was piloted or spawned — a pilot round's dev turn dispatched through the
    /// SAME `RunService`/`RunStore` a spawned round's does, so `devReportText(runId:)`
    /// already resolves it. The one genuinely new piece is `adoptionNote`
    /// (`RelayPMPrompt.Context`): rendered exactly once, on the FIRST spawned PM turn,
    /// telling the incoming PM that earlier rounds ran in Pilot mode so it reads the
    /// round log as its own relay's history, not a stranger's.
    ///
    /// `config.maxRounds`/`config.stagnationRoundCap` behave exactly like a spawned
    /// `run`/`resume` — supplied fresh by the caller every call, never read from the
    /// pilot relay's `pilotMaxRounds`/`pilotStagnationRoundCap` (those existed only
    /// because Pilot has no long-lived process to re-supply a config; a spawned loop
    /// always gets one fresh). Because `loop`'s ceiling check is `state.rounds.count +
    /// 1 > config.maxRounds`, and `state.rounds` already carries every piloted round,
    /// the ceiling counts TOTAL rounds — piloted plus spawned — never a fresh budget
    /// that pretends the piloted rounds didn't happen.
    public func adopt(
        relayId: String, pmWorkerId: String, config: Config, events: EventSink? = nil
    ) async -> Result<RelayState, AdoptError> {
        guard var state = stateStore.load(id: relayId) else { return .failure(.relayNotFound) }
        guard state.pmMode == .external else { return .failure(.notPilotRelay) }
        guard state.status == .awaitingPM || state.status == .escalated else {
            return .failure(.notAdoptable(status: state.status.rawValue))
        }

        let priorEscalationNote = state.status == .escalated ? state.note : nil
        let note = Self.adoptionNoteText(roundsSoFar: state.rounds.count, priorEscalationNote: priorEscalationNote)

        state.pmMode = .spawned
        state.pmWorkerId = pmWorkerId
        state.status = .running
        state.finishedAt = nil

        var adoptedConfig = config
        adoptedConfig.projectRoot = state.projectRoot
        adoptedConfig.docPath = state.docPath
        adoptedConfig.pmWorkerId = pmWorkerId
        adoptedConfig.devWorkerId = state.devWorkerId

        threadProjector?.started(state: state, projectId: config.projectId)
        persist(state)
        await loop(state: &state, config: adoptedConfig, events: events, adoptionNote: note)
        return .success(state)
    }

    private static func adoptionNoteText(roundsSoFar: Int, priorEscalationNote: String?) -> String {
        var text = """
        This relay's first \(roundsSoFar) round\(roundsSoFar == 1 ? "" : "s") ran in Pilot \
        mode (`docs/phases/Pilot_Relay.md`) — a live human/agent session held the PM seat \
        directly and wrote each handover itself; those rounds carry no `pmRunId`, their \
        submission IS the PM turn's run-truth. You are the spawned PM taking over this SAME \
        relay from here — read the doc fresh, review the actual commits in the range above \
        like any other round, and continue exactly where the piloting session left off.
        """
        if let priorEscalationNote, !priorEscalationNote.isEmpty {
            text += """
            \n\nThe piloting session had escalated with this open question before you were \
            adopted onto the relay — resolve it if it's still live, or proceed past it if \
            events have moved on: "\(priorEscalationNote)"
            """
        }
        return text
    }

    // MARK: - Reverse adopt (docs/phases/Pilot_Relay.md §5 "falls out of the same move")

    /// `alln pair pilot adopt` failure.
    public enum ReverseAdoptError: Swift.Error, Sendable, Equatable {
        case relayNotFound
        /// The relay isn't a spawned relay (`pmMode != .spawned`) — nothing to hand to
        /// a piloting session (it's already Pilot's).
        case notSpawnedRelay
        /// Anything other than a parked spawned relay (`RelayState.isResumable`) — a
        /// round in flight, a finished relay, or a ceiling-`stopped` one that never
        /// reconciled. Only a relay `relay-resume` would also accept is eligible here.
        case notAdoptable(status: String)
    }

    /// `alln pair pilot adopt --relay <id>` — the reverse of `adopt` above: hands a
    /// PARKED SPAWNED relay's PM seat to a piloting session. Genuinely trivial (`docs/
    /// phases/Pilot_Relay.md` §5 "falls out of the same move"): unlike `adopt`, this
    /// never dispatches anything and needs no `RunService` at all — a parked spawned
    /// relay (`RelayState.isResumable`: `escalated`, or ceiling-`stopped` and
    /// reconciled) is EXACTLY the set `relay-resume` already accepts, so this simply
    /// re-labels it `pmMode: .external`, `status: .awaitingPM`,
    /// `pmWorkerId: RelayState.externalPMWorkerId` and persists — the round log and
    /// thread carry over untouched, and the piloting session picks it up with an
    /// ordinary `pilot handoff` next. `static` for the same reason `reconcileOrphan`
    /// is: a plain state mutation shouldn't need a full `RelayCoordinator` (and the
    /// `RunService` its initializer requires) built just to flip two fields.
    @discardableResult
    public static func adoptToPilot(
        relayId: String, stateStore: RelayStateStore, threadProjector: RelayThreadProjector?,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> Result<RelayState, ReverseAdoptError> {
        guard let loaded = stateStore.load(id: relayId) else { return .failure(.relayNotFound) }
        let reconciled = reconcileOrphan(loaded, stateStore: stateStore, threadProjector: threadProjector, now: now)
        guard reconciled.pmMode == .spawned else { return .failure(.notSpawnedRelay) }
        guard reconciled.isResumable else { return .failure(.notAdoptable(status: reconciled.status.rawValue)) }

        var state = reconciled
        state.pmMode = .external
        state.pmWorkerId = RelayState.externalPMWorkerId
        state.status = .awaitingPM
        state.finishedAt = nil
        state.stoppedReason = nil
        try? stateStore.save(state)
        threadProjector?.sync(state: state, now: now())
        return .success(state)
    }

    /// Trailing streak of consecutive rounds — counted from the END of `rounds` — that
    /// `continued` with zero repo change (`baselineHead == headAfterDev`). Mirrors the
    /// spawned `loop()`'s in-memory `stagnationStreak`, recomputed fresh from the
    /// persisted round log each call since Pilot has no long-lived loop to carry a
    /// running counter across separate `pilot handoff` invocations.
    private func trailingStagnationStreak(_ rounds: [RelayRound]) -> Int {
        var streak = 0
        for round in rounds.reversed() {
            guard round.outcome == .continued, round.baselineHead == round.headAfterDev else { break }
            streak += 1
        }
        return streak
    }

    /// Resumes an `.escalated` relay (a real founder question) OR a reconciled-`.stopped`
    /// one (`RelayState.isReconciledStopped` — its owner process died mid-round; works-test
    /// hazard #1: "escalated-only was too narrow"): injects the founder's answer as
    /// `founderNote` for the next PM turn, then continues the loop from the last durable
    /// round. `config` re-supplies the ceilings (`maxRounds`/`until`/`stagnationRoundCap`)
    /// — these are per-invocation, not part of the persisted `RelayState`, so a resumed run
    /// can widen or tighten them (e.g. a fresh `--until` for the next stretch);
    /// `projectRoot`/`docPath`/worker ids are taken from the loaded state, not `config`, so
    /// a resume can never silently redirect a relay at a different doc or repo. Returns
    /// `nil` when no such relay exists, or its status isn't resumable (`.done`, or a
    /// ceiling-fired `.stopped` — a deliberate stop, never silently resumable) — the caller
    /// (CLI/MCP) turns that into a clean, honest error rather than the coordinator guessing.
    public func resume(relayId: String, founderAnswer: String, config: Config, events: EventSink? = nil) async -> RelayState? {
        guard let loaded = stateStore.load(id: relayId) else { return nil }
        var state = reconcileIfOrphaned(loaded)
        guard state.isResumable else { return nil }
        var resumedConfig = config
        resumedConfig.projectRoot = state.projectRoot
        resumedConfig.docPath = state.docPath
        resumedConfig.pmWorkerId = state.pmWorkerId
        resumedConfig.devWorkerId = state.devWorkerId

        state.founderNote = founderAnswer
        state.status = .running
        state.finishedAt = nil
        // Re-affirms the thread's projectId (a no-op when already bound) and guarantees
        // the thread exists even if the original `run()` call never had a projector
        // attached — `sync` below is then guaranteed a thread to project onto.
        threadProjector?.started(state: state, projectId: config.projectId)
        persist(state)
        await loop(state: &state, config: resumedConfig, events: events)
        return state
    }

    /// `pair relay-status` / MCP `pair_relay(action: status)` — the read path that also
    /// reconciles (works-test hazard #1: "on load/list/status/start"). Returns `nil` only
    /// when no such relay exists.
    public func status(relayId: String) -> RelayState? {
        guard let state = stateStore.load(id: relayId) else { return nil }
        return reconcileIfOrphaned(state)
    }

    /// Reconciles a `.running` relay whose owner process died mid-round back to a durable
    /// `.stopped`, using this coordinator's own `stateStore`/`threadProjector`. Delegates to
    /// `RelayCoordinator.reconcileOrphan` — the standalone, static, `RunService`-free
    /// implementation `RelayCLI.runStatus`/`MCPRelayHandlers.status` also call directly for a
    /// plain status read (building a full coordinator there would mean spinning up a
    /// `RunService` for a read-only check).
    @discardableResult
    private func reconcileIfOrphaned(_ state: RelayState) -> RelayState {
        Self.reconcileOrphan(state, stateStore: stateStore, threadProjector: threadProjector, now: now)
    }

    /// The ONE place orphan reconciliation happens (works-test hazard #1: "on
    /// load/list/status/start") — `RelayCoordinator.status`/`resume` (above) and
    /// `RelayCLI.runStatus`/`MCPRelayHandlers.status` (which have no `RunService` to build a
    /// full coordinator from) all funnel through this static, `RunService`-free function, so
    /// the brief's four read paths can never drift into separate half-implementations.
    /// Mirrors `PairCoordinator.reconcileStaleRunning`'s write-back-on-detection shape,
    /// using `RelayStateStore.isOwnerDead`'s owner.pid liveness signal (the same convention
    /// `RunStore` uses). Settles the round in flight (if it hadn't already recorded an
    /// outcome) so `RelayThreadProjector.sync`'s existing self-heal branches in
    /// `syncPMTurn`/`syncDevTurn` close the open PM/dev thread turn and `syncStopped` records
    /// the stopped system event. A no-op — returns `state` unchanged, no save, no sync — for
    /// anything other than a dead-owner `.running` relay: a genuinely live `.running` relay,
    /// or one already `.done`/`.escalated`/`.stopped`, passes through untouched.
    ///
    /// This `.running`-only guard is also what makes a Pilot relay's parked
    /// `awaitingPM` (`docs/phases/Pilot_Relay.md` PL-S01) immune to orphan
    /// reconciliation — a pilot relay can sit `awaitingPM` for days between
    /// `pilot handoff` calls with no process behind it, and that is never mistaken
    /// for a dead owner. Only the brief window where `runExternalRound` itself
    /// flips a pilot relay to `.running` while a dev turn is in flight is ever
    /// reconciliation-eligible, exactly like a spawned round.
    @discardableResult
    public static func reconcileOrphan(
        _ state: RelayState, stateStore: RelayStateStore,
        threadProjector: RelayThreadProjector?, now: @escaping @Sendable () -> Date
    ) -> RelayState {
        guard state.status == .running, stateStore.isOwnerDead(id: state.id) else { return state }
        var reconciled = state
        if let lastIndex = reconciled.rounds.indices.last, reconciled.rounds[lastIndex].outcome == nil {
            reconciled.rounds[lastIndex].outcome = .stopped
            reconciled.rounds[lastIndex].finishedAt = now()
        }
        reconciled.status = .stopped
        reconciled.stoppedReason = RelayState.orphanReconciledReason
        reconciled.finishedAt = now()
        try? stateStore.save(reconciled)
        threadProjector?.sync(state: reconciled, now: now())
        return reconciled
    }

    // MARK: - Loop

    /// The round-after-round driver (PM_Relay.md §2). Checks ceilings BEFORE each round
    /// (`maxRounds`, `until`) and re-checks the stagnation counter AFTER each round that
    /// continued — a round that ends any other way (`done`/`escalated`/a mid-round
    /// deadline stop) already returned from `runRound` having persisted its own terminal
    /// state, so the loop just returns.
    private func loop(state: inout RelayState, config: Config, events: EventSink?, adoptionNote: String? = nil) async {
        var stagnationStreak = 0
        // Consumed after the FIRST round attempt this `loop` call makes (win or lose) —
        // `RelayCoordinator.adopt`'s note is a one-time "here's the story so far" for
        // the very next PM turn, never repeated on later rounds of the same call.
        var pendingAdoptionNote = adoptionNote
        while true {
            let roundNumber = state.rounds.count + 1
            if roundNumber > config.maxRounds {
                stop(&state, reason: "reached --max-rounds (\(config.maxRounds))")
                events?(.stopped(reason: state.stoppedReason ?? ""))
                return
            }
            if isPastDeadline(config) {
                stop(&state, reason: "--until deadline reached before round \(roundNumber)")
                events?(.stopped(reason: state.stoppedReason ?? ""))
                return
            }

            let result = await runRound(state: &state, config: config, roundNumber: roundNumber, events: events, adoptionNote: pendingAdoptionNote)
            pendingAdoptionNote = nil
            switch result {
            case .done, .escalated, .stoppedMidRound:
                return
            case .continued:
                // Stagnation approximates the doc's --max-consecutive-flags (§5 item 3):
                // N consecutive rounds where the dev turn produced ZERO repo change AND the
                // verdict was `continue` reads as a probable PM↔dev deadlock (the PM keeps
                // asking for the same thing, the dev keeps not delivering it) rather than
                // genuine progress. A round that itself escalated/stopped never reaches
                // here, so this only measures rounds that legitimately continued.
                if let last = state.rounds.last, last.outcome == .continued,
                   last.baselineHead == last.headAfterDev {
                    stagnationStreak += 1
                } else {
                    stagnationStreak = 0
                }
                if stagnationStreak >= config.stagnationRoundCap {
                    stop(&state, reason: "stagnation: \(stagnationStreak) consecutive rounds with no repo change and verdict continue — likely PM↔dev deadlock")
                    events?(.stopped(reason: state.stoppedReason ?? ""))
                    return
                }
            }
        }
    }

    private enum RoundResult {
        case continued
        case done
        case escalated
        case stoppedMidRound
    }

    /// One full round (PM_Relay.md §2 steps 1–6): pin baseline, PM turn (+ one re-ask on an
    /// unparseable verdict), `HandoverGate`, dev turn, pin the post-dev HEAD. Persists the
    /// round after EVERY state change so a crash or `--until` stop mid-round leaves a
    /// resumable, honest record rather than a half-written one.
    private func runRound(state: inout RelayState, config: Config, roundNumber: Int, events: EventSink?, adoptionNote: String? = nil) async -> RoundResult {
        events?(.roundStarted(round: roundNumber))

        let baselineHead = gitObserver.observe(rootPath: config.projectRoot).head
        var round = RelayRound(roundNumber: roundNumber, baselineHead: baselineHead, startedAt: now())
        state.rounds.append(round)
        persist(state)

        // Thread the review range for THIS round's PM prompt from the PREVIOUS round: the
        // previous round's own baselineHead (pinned before ITS PM turn — so a PM
        // self-mutation in that round is included) through its headAfterDev (after that
        // round's dev turn). Round 1 has neither — no dev report, no range to show.
        let previousRound = roundNumber > 1 ? state.rounds[state.rounds.count - 2] : nil
        let devReport = previousRound?.devRunId.flatMap { devReportText(runId: $0) }
        let founderNote = state.founderNote
        let pmContext = RelayPMPrompt.Context(
            docPath: config.docPath,
            roundNumber: roundNumber,
            baselineHead: previousRound?.baselineHead ?? baselineHead ?? "",
            currentHead: previousRound?.headAfterDev,
            devReport: devReport,
            founderNote: founderNote,
            adoptionNote: adoptionNote,
            maxRounds: config.maxRounds,
            roundsRemaining: max(0, config.maxRounds - roundNumber + 1)
        )
        if founderNote != nil {
            // One-time injection into "the next PM turn" (brief) — never restated.
            state.founderNote = nil
            persist(state)
        }

        let pmRequest = RunRequest(
            message: RelayPMPrompt.assemble(context: pmContext),
            repoRoot: config.projectRoot, projectId: config.projectId,
            presetId: config.presetId, workerId: config.pmWorkerId
        )
        let pmDispatch = await dispatchTurn(pmRequest, config: config)

        let pmOutput: String
        switch pmDispatch {
        case .deadline:
            return finishRound(&state, &round, outcome: .stopped, events: events) {
                stop(&$0, reason: "--until deadline reached during the PM turn (round \(roundNumber))")
                events?(.stopped(reason: $0.stoppedReason ?? ""))
            }
        case .serviceError(let error):
            return finishRound(&state, &round, outcome: .escalated, events: events) {
                escalate(&$0, note: "PM turn failed to dispatch: \(error.description)")
                events?(.escalated(note: $0.note ?? ""))
            }
        case .budgetExhausted(let reason):
            return finishRound(&state, &round, outcome: .escalated, events: events) {
                escalate(&$0, note: "PM turn \(reason) (round \(roundNumber))")
                events?(.escalated(note: $0.note ?? ""))
            }
        case .delivered(let run, let output):
            round.pmRunId = run.id
            state.rounds[state.rounds.count - 1] = round
            persist(state)
            pmOutput = output
        }

        // Parse the verdict tail; one re-ask (same PM seat) on failure, then escalate.
        var extraction: RelayVerdictParser.Extraction
        switch RelayVerdictParser.extract(from: pmOutput) {
        case .success(let ex):
            extraction = ex
        case .failure(let parseError):
            let reaskRequest = RunRequest(
                message: RelayReaskPrompt.assemble(previousOutput: pmOutput, parseError: parseError),
                repoRoot: config.projectRoot, projectId: config.projectId,
                presetId: config.presetId, workerId: config.pmWorkerId
            )
            let reaskDispatch = await dispatchTurn(reaskRequest, config: config)
            switch reaskDispatch {
            case .deadline:
                return finishRound(&state, &round, outcome: .stopped, events: events) {
                    stop(&$0, reason: "--until deadline reached during the PM re-ask (round \(roundNumber))")
                    events?(.stopped(reason: $0.stoppedReason ?? ""))
                }
            case .serviceError(let error):
                return finishRound(&state, &round, outcome: .escalated, events: events) {
                    escalate(&$0, note: "PM re-ask failed to dispatch: \(error.description)")
                    events?(.escalated(note: $0.note ?? ""))
                }
            case .budgetExhausted(let reason):
                return finishRound(&state, &round, outcome: .escalated, events: events) {
                    escalate(&$0, note: "PM re-ask \(reason) (round \(roundNumber))")
                    events?(.escalated(note: $0.note ?? ""))
                }
            case .delivered(let reaskRun, let reaskOutput):
                round.pmRunId = reaskRun.id
                state.rounds[state.rounds.count - 1] = round
                persist(state)
                switch RelayVerdictParser.extract(from: reaskOutput) {
                case .success(let ex):
                    extraction = ex
                case .failure:
                    return finishRound(&state, &round, outcome: .escalated, events: events) {
                        escalate(&$0, note: "PM did not produce a parseable RelayVerdict after one re-ask (round \(roundNumber))")
                        events?(.escalated(note: $0.note ?? ""))
                    }
                }
            }
        }

        round.verdict = extraction.verdict
        state.rounds[state.rounds.count - 1] = round
        persist(state)
        events?(.pmTurnFinished(round: roundNumber, verdict: extraction.verdict.verdict))

        switch extraction.verdict.verdict {
        case .done:
            return finishRound(&state, &round, outcome: .done, events: events) {
                finish(&$0, note: extraction.verdict.note)
                events?(.done(note: $0.note))
            }
        case .escalate:
            return finishRound(&state, &round, outcome: .escalated, events: events) {
                escalate(&$0, note: extraction.verdict.note ?? "PM escalated with no note (round \(roundNumber))")
                events?(.escalated(note: $0.note ?? ""))
            }
        case .continueRelay:
            // `RelayVerdictParser` already guarantees a non-empty `handover` for `continue`.
            guard let handover = extraction.verdict.handover else {
                return finishRound(&state, &round, outcome: .escalated, events: events) {
                    escalate(&$0, note: "PM verdict continue but handover was empty after parsing (round \(roundNumber))")
                    events?(.escalated(note: $0.note ?? ""))
                }
            }

            let gateDecision = HandoverGate.evaluate(handoverText: handover)
            round.gate = RelayGateSummary(decision: gateDecision)
            state.rounds[state.rounds.count - 1] = round
            persist(state)

            if case .blocked(let dangerClass, let code, let reason, let snippet) = gateDecision {
                events?(.gateBlocked(round: roundNumber, dangerClass: dangerClass.rawValue, reason: reason))
                return finishRound(&state, &round, outcome: .escalated, events: events) {
                    escalate(&$0, note: "HandoverGate blocked (\(dangerClass.rawValue), \(code)): \(reason) — \"\(snippet)\"")
                    events?(.escalated(note: $0.note ?? ""))
                }
            }

            let devDisplayName = await runService.workerDisplayName(forModelId: config.devWorkerId)
            let devRequest = RunRequest(
                message: RelayDevPrompt.assemble(context: .init(
                    handover: handover, docPath: config.docPath, roundNumber: roundNumber,
                    workerDisplayName: devDisplayName)),
                repoRoot: config.projectRoot, projectId: config.projectId,
                presetId: config.presetId, workerId: config.devWorkerId
            )
            let devDispatch = await dispatchTurn(devRequest, config: config)
            switch devDispatch {
            case .deadline:
                return finishRound(&state, &round, outcome: .stopped, events: events) {
                    stop(&$0, reason: "--until deadline reached during the dev turn (round \(roundNumber))")
                    events?(.stopped(reason: $0.stoppedReason ?? ""))
                }
            case .serviceError(let error):
                return finishRound(&state, &round, outcome: .escalated, events: events) {
                    escalate(&$0, note: "dev turn failed to dispatch: \(error.description)")
                    events?(.escalated(note: $0.note ?? ""))
                }
            case .budgetExhausted(let reason):
                return finishRound(&state, &round, outcome: .escalated, events: events) {
                    escalate(&$0, note: "dev turn \(reason) (round \(roundNumber))")
                    events?(.escalated(note: $0.note ?? ""))
                }
            case .delivered(let devRun, _):
                round.devRunId = devRun.id
                round.headAfterDev = gitObserver.observe(rootPath: config.projectRoot).head
                round.outcome = .continued
                round.finishedAt = now()
                state.rounds[state.rounds.count - 1] = round
                persist(state)
                events?(.devTurnFinished(round: roundNumber))
                return .continued
            }
        }
    }

    /// Stamps the round's outcome/finishedAt, persists it, applies the terminal
    /// `RelayState` transition (`apply`, which itself persists), and returns the matching
    /// `RoundResult`.
    @discardableResult
    private func finishRound(
        _ state: inout RelayState, _ round: inout RelayRound,
        outcome: RelayRound.Outcome, events: EventSink?, apply: (inout RelayState) -> Void
    ) -> RoundResult {
        round.outcome = outcome
        round.finishedAt = now()
        if !state.rounds.isEmpty { state.rounds[state.rounds.count - 1] = round }
        persist(state)
        apply(&state)
        switch outcome {
        case .done: return .done
        case .escalated: return .escalated
        case .stopped: return .stoppedMidRound
        case .continued: return .continued // unreachable from this helper's call sites
        }
    }

    // MARK: - Turn dispatch (bounded retry, RelayTurnClassifier)

    private enum TurnDispatch {
        case delivered(TeamRun, String)
        case budgetExhausted(String)
        case deadline
        case serviceError(RunServiceError)
    }

    /// Dispatches ONE turn through `RunService`, retrying on `.stalled`/`.emptyResult`/
    /// `.infraBackoff`/`.compacting` per `RelayTurnClassifier.RetryCeiling` (a bare retry —
    /// simpler than `PairCoordinator`'s nudge-prompt retries, since the relay's retries are
    /// for infra hiccups/compaction/hangs, not "your check failed, try differently"; the PM
    /// or dev's own free prose already carries anything it needs to try differently).
    /// `--until` is honored between attempts (mirrors QUEUE-S02).
    private func dispatchTurn(_ request: RunRequest, config: Config) async -> TurnDispatch {
        var stalledAttempts = 0
        var emptyAttempts = 0
        var infraAttempts = 0
        var compactionAttempts = 0

        while true {
            if isPastDeadline(config) { return .deadline }

            let result = await runService.run(request, origin: .cli)
            guard case .success(let run) = result else {
                if case .failure(let error) = result { return .serviceError(error) }
                return .serviceError(.noWorker("relay turn dispatch failed"))
            }
            let outcome = run.workerAnswers.first?.result
                ?? WorkerRunOutcome(status: .failed, errorReason: "no worker answer")

            switch RelayTurnClassifier.classify(.init(outcome: outcome)) {
            case .delivered(let text):
                return .delivered(run, text)
            case .stalled:
                stalledAttempts += 1
                if stalledAttempts > RelayTurnClassifier.RetryCeiling.maxStalledAttempts {
                    return .budgetExhausted("stalled repeatedly (\(stalledAttempts) attempts)")
                }
            case .emptyResult:
                emptyAttempts += 1
                if emptyAttempts > RelayTurnClassifier.RetryCeiling.maxEmptyResultAttempts {
                    return .budgetExhausted("returned empty output repeatedly (\(emptyAttempts) attempts)")
                }
            case .infraBackoff:
                infraAttempts += 1
                if infraAttempts > RelayTurnClassifier.RetryCeiling.maxInfraBackoffAttempts {
                    return .budgetExhausted("infra backoff budget exhausted (\(infraAttempts) attempts)")
                }
                await sleepClampedToDeadline(config, seconds: RelayTurnClassifier.RetryCeiling.infraBackoffGraceSeconds)
            case .compacting:
                compactionAttempts += 1
                if compactionAttempts > RelayTurnClassifier.RetryCeiling.maxCompactionAttempts {
                    return .budgetExhausted("still compacting after \(compactionAttempts) retries")
                }
                await sleepClampedToDeadline(config, seconds: RelayTurnClassifier.RetryCeiling.compactionGraceSeconds)
            }

            if isPastDeadline(config) { return .deadline }
        }
    }

    // MARK: - Small helpers

    private func devReportText(runId: String) -> String? {
        runStore.load(runId: runId)?.workerAnswers.first?.output
    }

    private func stop(_ state: inout RelayState, reason: String) {
        state.status = .stopped
        state.stoppedReason = reason
        state.finishedAt = now()
        persist(state)
    }

    private func escalate(_ state: inout RelayState, note: String) {
        state.status = .escalated
        state.note = note
        state.finishedAt = now()
        persist(state)
    }

    private func finish(_ state: inout RelayState, note: String?) {
        state.status = .done
        state.note = note
        state.finishedAt = now()
        persist(state)
    }

    /// The single choke point every `RelayState` mutation already runs through — the
    /// natural, minimal-diff hook for `threadProjector?.sync` (R-S07): it fires
    /// synchronously right after each state change, so a round's escalation note is
    /// always captured before a LATER round could overwrite `state.note`.
    private func persist(_ state: RelayState) {
        try? stateStore.save(state)
        threadProjector?.sync(state: state, now: now())
    }

    private func isPastDeadline(_ config: Config) -> Bool {
        guard let until = config.until else { return false }
        return now() >= until
    }

    private func sleepClampedToDeadline(_ config: Config, seconds: Int) async {
        var sleepNs = UInt64(max(0, seconds)) * 1_000_000_000
        if let until = config.until {
            let remaining = until.timeIntervalSince(now())
            if remaining <= 0 { return }
            sleepNs = min(sleepNs, UInt64(max(0, remaining) * 1_000_000_000))
        }
        if sleepNs > 0 {
            try? await Task.sleep(nanoseconds: sleepNs)
        }
    }
}
