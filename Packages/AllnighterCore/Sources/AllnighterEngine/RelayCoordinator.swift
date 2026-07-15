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
        /// Plumbed per the brief: PM turns already run under the same mutating,
        /// write-lock-disciplined path as everything else (§4.2 — "mechanically free").
        /// Mechanical read-only enforcement (an answer-shape PM seat, `--pm-read-only`) is
        /// a named follow-up — this flag does not yet change dispatch behavior.
        public var pmMayMutate: Bool
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
            pmMayMutate: Bool = true,
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
            self.pmMayMutate = pmMayMutate
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

    /// Resumes an `.escalated` relay: injects the founder's answer as `founderNote` for the
    /// next PM turn, then continues the loop. `config` re-supplies the ceilings
    /// (`maxRounds`/`until`/`stagnationRoundCap`) — these are per-invocation, not part of
    /// the persisted `RelayState`, so a resumed run can widen or tighten them (e.g. a fresh
    /// `--until` for the next stretch); `projectRoot`/`docPath`/worker ids are taken from
    /// the loaded state, not `config`, so a resume can never silently redirect a relay at a
    /// different doc or repo. Returns `nil` when no such relay exists or it isn't
    /// `.escalated` (the only resumable status) — the caller (CLI/MCP) turns that into a
    /// clean, honest error rather than the coordinator guessing.
    public func resume(relayId: String, founderAnswer: String, config: Config, events: EventSink? = nil) async -> RelayState? {
        guard var state = stateStore.load(id: relayId), state.status == .escalated else { return nil }
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

    // MARK: - Loop

    /// The round-after-round driver (PM_Relay.md §2). Checks ceilings BEFORE each round
    /// (`maxRounds`, `until`) and re-checks the stagnation counter AFTER each round that
    /// continued — a round that ends any other way (`done`/`escalated`/a mid-round
    /// deadline stop) already returned from `runRound` having persisted its own terminal
    /// state, so the loop just returns.
    private func loop(state: inout RelayState, config: Config, events: EventSink?) async {
        var stagnationStreak = 0
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

            let result = await runRound(state: &state, config: config, roundNumber: roundNumber, events: events)
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
    private func runRound(state: inout RelayState, config: Config, roundNumber: Int, events: EventSink?) async -> RoundResult {
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

            let devRequest = RunRequest(
                message: RelayDevPrompt.assemble(context: .init(handover: handover, docPath: config.docPath, roundNumber: roundNumber)),
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
