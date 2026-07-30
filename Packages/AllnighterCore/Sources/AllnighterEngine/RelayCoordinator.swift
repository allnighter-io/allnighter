import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import AllnighterCore

/// PM Relay control plane (docs/phases/PM_Relay.md §2) — the turn-based, unattended
/// PM↔dev loop that replaces the founder's copy-paste relay. Mirrors `PairCoordinator`'s
/// shape: a plain `Sendable` struct whose async methods drive the actor-isolated
/// `RunService`; no isolation of its own is needed because every mutating step already
/// runs sequentially through `RunService`'s write lock, and the one-mutating-worker
/// invariant holds by construction (turns never overlap).
///
/// Every turn — PM or dev — dispatches through the SAME `RunService.run` path used by
/// ordinary chat/execution, under `build_slice` (a single mutating worker), with
/// `workerId` pinned to the relay's PM or dev seat. Allnighter never invents a second
/// dispatch route (PM_Relay.md §5 item 2).
public struct RelayCoordinator: Sendable {
    public struct Config: Sendable {
        public var projectRoot: String
        public var projectId: String?
        /// Repo-relative path to the spec doc — never a payload; the PM re-reads it fresh
        /// from disk each round (PM_Relay.md §2, "the doc is an anchor, not a payload").
        public var docPath: String
        public var pmModelId: String
        public var devModelId: String
        public var maxRounds: Int
        public var until: Date?
        /// Consecutive rounds with zero repo change AND verdict `continue` before the
        /// relay stops itself as a probable PM↔dev deadlock. Approximates the doc's
        /// `--max-consecutive-flags` (§5 item 3) — see `RelayCoordinator.loop`.
        public var stagnationRoundCap: Int
        /// The single-mutating-worker team both seats run under. Defaults to
        /// `build_slice` (`PairCoordinator.Seats` uses the same team for its
        /// executor seat).
        public var presetId: String
        /// PO-S04: hard timeout (seconds) for each harness-owned proof command.
        /// Defaults to `ProjectVerificationService.defaultTimeoutSeconds` (600).
        public var proofTimeoutSeconds: Int
        /// PO-S03/S04: how long a blocked **dev turn** waits on the execution lane
        /// before failing with `laneBusy`. Defaults to the generous production bound.
        public var executionLaneWaitTimeout: Duration
        /// PO-S04: how long the proof phase waits on the execution lane after the
        /// dev turn releases it. Defaults to the same generous bound as the turn.
        public var proofLaneWaitTimeout: Duration
        /// PO-F7: override the dev seat's per-turn worker idle-stall budget
        /// (`RunRequest.workerTimeoutSeconds`, reusing PO-F5's field + runner plumbing).
        /// `nil` (default) leaves the driver manifest's idle timeout untouched.
        public var devTurnIdleTimeoutSeconds: Int?
        /// ATL-S01: founder kickoff brief for the first PM turn only. Optional;
        /// when set, persisted on claim and consume-once cleared after the first
        /// PM prompt assemble. Never written into `founderNote` (resume-only).
        public var kickoffMessage: String?

        public init(
            projectRoot: String,
            projectId: String? = nil,
            docPath: String,
            pmModelId: String,
            devModelId: String,
            maxRounds: Int = 20,
            until: Date? = nil,
            stagnationRoundCap: Int = 3,
            presetId: String = "build_slice",
            proofTimeoutSeconds: Int = ProjectVerificationService.defaultTimeoutSeconds,
            executionLaneWaitTimeout: Duration = .seconds(1800),
            proofLaneWaitTimeout: Duration = .seconds(1800),
            devTurnIdleTimeoutSeconds: Int? = nil,
            kickoffMessage: String? = nil
        ) {
            self.projectRoot = projectRoot
            self.projectId = projectId
            self.docPath = docPath
            self.pmModelId = pmModelId
            self.devModelId = devModelId
            self.maxRounds = max(1, maxRounds)
            self.until = until
            self.stagnationRoundCap = max(1, stagnationRoundCap)
            self.presetId = presetId
            self.proofTimeoutSeconds = max(1, proofTimeoutSeconds)
            self.executionLaneWaitTimeout = executionLaneWaitTimeout
            self.proofLaneWaitTimeout = proofLaneWaitTimeout
            self.devTurnIdleTimeoutSeconds = devTurnIdleTimeoutSeconds
            self.kickoffMessage = kickoffMessage
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
    /// PTD-1b: durable delivery receipt written before a relay parks or settles.
    private let pmTurnStore: PMTurnStore
    /// Optional (PM_Relay.md §6 R-S07): projects the relay onto a `WorkThread` so the
    /// Mac inbox shows the loop live. Pure composition — `nil` by default so every
    /// existing test/headless caller keeps working unchanged; CLI/MCP construct one via
    /// `RelayDispatch.makeCoordinator` so real relays always show in the inbox.
    private let threadProjector: RelayThreadProjector?
    /// Per-root build/execution lane (PO-S03). Shared with `RunWriteLock` — one system.
    private let executionLane: ExecutionLaneRegistry
    /// PO-S04: process-group runner for harness proofs only. Separate from
    /// `RunService`'s worker runner so tests can mock workers while proofs still
    /// exercise real `ProcessGroupCommandRunner` (or a dedicated double). Never a
    /// second spawn *implementation* — same `ProcessGroupCommandRunner` type.
    private let proofCommandRunner: CommandRunner
    private let now: @Sendable () -> Date
    private let idFactory: @Sendable () -> String

    /// How long a blocked dev turn waits on the execution lane before failing with
    /// `laneBusy`. Generous: normal holders finish in minutes; this is the wedged-holder
    /// safety valve (mirrors `RunService.writeLockWaitTimeout`).
    static let executionLaneWaitTimeout: Duration = .seconds(1800)

    public init(
        runService: RunService,
        gitObserver: GitObserver = GitObserver(),
        stateStore: RelayStateStore = RelayStateStore(),
        runStore: RunStore = RunStore(),
        pmTurnStore: PMTurnStore? = nil,
        threadProjector: RelayThreadProjector? = nil,
        executionLane: ExecutionLaneRegistry = .shared,
        proofCommandRunner: CommandRunner = ProcessGroupCommandRunner(
            environmentPolicy: AllnighterSpawnEnvironmentPolicy(),
            spawnKind: .harnessProof
        ),
        now: @escaping @Sendable () -> Date = Date.init,
        idFactory: @escaping @Sendable () -> String = RelayCoordinator.mintRelayId
    ) {
        self.runService = runService
        self.gitObserver = gitObserver
        self.stateStore = stateStore
        self.runStore = runStore
        // A supplied state-store root (the normal test seam) must carry its PM
        // receipt beside it; production's default state store resolves to the same
        // Allnighter relays root as `PMTurnStore()`.
        self.pmTurnStore = pmTurnStore ?? PMTurnStore(relaysRootDirectory: stateStore.rootDirectory)
        self.threadProjector = threadProjector
        self.executionLane = executionLane
        self.proofCommandRunner = proofCommandRunner
        self.now = now
        self.idFactory = idFactory
    }

    /// The default `idFactory` format, exposed so RSC-S03's `pair relay --no-wait`
    /// foreground step can pre-mint an id in the SAME format `run(config:)` would have
    /// generated internally — one format, not two drifting copies of the string
    /// template.
    public static func mintRelayId() -> String {
        "relay_\(UUID().uuidString.lowercased())"
    }

    // MARK: - Entry points

    /// RSC-S02: non-mutating duplicate-start check. Scans `stateStore.list()` for a
    /// relay with a matching normalized `projectRoot` + normalized `docPath`, `status ==
    /// .running`, and a LIVE owner (`!stateStore.isOwnerDead(id:)`) — a dead-owner
    /// `.running` relay is an orphan, not a live duplicate, and must never block a new
    /// start (that is `reconcileOrphan`'s job, not this one's). Parked relays
    /// (`awaitingPM`/`escalated`) never match: they need `resume`/`adopt`, not a
    /// competing new relay, and refusing a start because one exists would break
    /// Pilot's long-parked-by-design flow. `run` below calls this UNDER its start-key
    /// lock so the scan and the new relay's first persist are one atomic window across
    /// processes; a foreground caller (e.g. a CLI ack-before-dispatch check) may also
    /// call this standalone for an early, lock-free read — a `.success` here is not a
    /// guarantee against a start that lands between the check and the real call.
    public static func preflightStart(
        projectRoot: String, docPath: String, stateStore: RelayStateStore
    ) -> Result<Void, DispatchRefusal> {
        let normalizedRoot = RootNormalization.normalize(projectRoot).key
        let normalizedDoc = RelayDispatchLock.normalizeDocPath(docPath)
        for candidate in stateStore.list() {
            guard candidate.status == .running,
                  RelayDispatchLock.normalizeDocPath(candidate.docPath) == normalizedDoc else { continue }
            guard RootNormalization.normalize(candidate.projectRoot).key == normalizedRoot else { continue }
            guard !stateStore.isOwnerDead(id: candidate.id) else { continue }
            return .failure(.alreadyActive(relayId: candidate.id))
        }
        return .success(())
    }

    /// RSC-HF: durable start claim only (lock + preflight + first `.running` persist).
    /// GUI navigates after this succeeds; `complete` runs the round loop in the background.
    /// `run` is claimStart + complete.
    public func claimStart(config: Config, id: String? = nil) -> Result<RelayState, DispatchRefusal> {
        let key = RelayDispatchLock.startKey(projectRoot: config.projectRoot, docPath: config.docPath)
        guard let acquired = RelayDispatchLock.acquireStart(startKey: key, relaysRoot: stateStore.rootDirectory) else {
            if case .failure(let refusal) = Self.preflightStart(
                projectRoot: config.projectRoot, docPath: config.docPath, stateStore: stateStore
            ) { return .failure(refusal) }
            return .failure(.journalUnavailable)
        }
        var lockHandle: ThreadFlockLock.Handle? = acquired

        if case .failure(let refusal) = Self.preflightStart(
            projectRoot: config.projectRoot, docPath: config.docPath, stateStore: stateStore
        ) {
            lockHandle = nil
            return .failure(refusal)
        }

        let state = RelayState(
            id: id ?? idFactory(),
            projectRoot: config.projectRoot,
            docPath: config.docPath,
            pmModelId: config.pmModelId,
            devModelId: config.devModelId,
            status: .running,
            createdAt: now(),
            kickoffMessage: config.kickoffMessage
        )
        threadProjector?.started(state: state, projectId: config.projectId)
        do {
            try persistClaim(state)
        } catch {
            lockHandle = nil
            return .failure(.journalUnavailable)
        }
        lockHandle = nil
        return .success(state)
    }

    /// Runs the round loop for a relay that `claimStart` (or an equivalent guard) already
    /// flipped to `.running`.
    public func complete(
        _ claimed: RelayState,
        config: Config,
        events: EventSink? = nil
    ) async {
        var state = claimed
        await loop(state: &state, config: config, events: events)
    }

    /// Starts a new relay and runs it to a terminal `RelayState` (`done`, `escalated`, or
    /// `stopped`). Every round is persisted the moment it changes (durable mid-round).
    public func run(config: Config, id: String? = nil, events: EventSink? = nil) async -> Result<RelayState, DispatchRefusal> {
        switch claimStart(config: config, id: id) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(var state):
            await loop(state: &state, config: config, events: events)
            return .success(state)
        }
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
    /// invocation. `config.pmModelId` is ignored; the durable `pmModelId` is always
    /// `RelayState.externalPMModelId` (there is no PM model to dispatch).
    public func startPilot(config: Config) -> Result<RelayState, PilotStartError> {
        guard config.until == nil else { return .failure(.untilNotSupported) }
        let state = RelayState(
            id: idFactory(),
            projectRoot: config.projectRoot,
            docPath: config.docPath,
            pmModelId: RelayState.externalPMModelId,
            devModelId: config.devModelId,
            status: .awaitingPM,
            pmMode: .external,
            createdAt: now(),
            pilotMaxRounds: config.maxRounds,
            pilotStagnationRoundCap: config.stagnationRoundCap,
            pilotDevTurnIdleTimeoutSeconds: config.devTurnIdleTimeoutSeconds
        )
        threadProjector?.started(state: state, projectId: config.projectId)
        persist(state)
        return .success(state)
    }

    /// Non-mutating preflight shared by blocking `runExternalRound` and
    /// `pilot handoff --no-wait`. Failures leave durable state untouched — the
    /// same cases a blocking call would refuse before flipping `.running`.
    ///
    /// Does **not** apply max-rounds / stagnation ceilings (those intentionally
    /// settle the relay and remain on the full round path). For `continue`,
    /// runs `HandoverGate` so a detached dispatch cannot ack `"dispatched"`
    /// while the child silently dumps `RELAY_HANDOVER_UNSAFE` to `/dev/null`.
    public static func preflightExternalRound(
        state: RelayState?,
        submission: String
    ) -> Result<(state: RelayState, extraction: RelayVerdictParser.Extraction), PilotRoundError> {
        guard let state else { return .failure(.relayNotFound) }
        guard state.pmMode == .external else { return .failure(.notPilotRelay) }
        if state.status == .running { return .failure(.roundInFlight) }
        guard state.status == .awaitingPM else {
            return .failure(.notAwaitingPM(status: state.status.rawValue))
        }

        let extraction: RelayVerdictParser.Extraction
        switch RelayVerdictParser.extract(from: submission) {
        case .success(let ex):
            extraction = ex
        case .failure(let parseError):
            return .failure(.verdictUnparseable(parseError))
        }

        if case .continueRelay = extraction.verdict.verdict {
            guard let handover = extraction.verdict.handover,
                  !handover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.verdictUnparseable(.continueWithoutHandover))
            }
            let gateDecision = HandoverGate.evaluate(handoverText: handover)
            if case .blocked(let dangerClass, let code, let reason, let snippet) = gateDecision {
                return .failure(.handoverBlocked(
                    dangerClass: dangerClass.rawValue,
                    code: code,
                    reason: reason,
                    snippet: snippet
                ))
            }
        }
        return .success((state, extraction))
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
        let loaded = stateStore.load(id: relayId)
        let preflight = Self.preflightExternalRound(state: loaded, submission: submission)
        var state: RelayState
        let extraction: RelayVerdictParser.Extraction
        switch preflight {
        case .failure(let error):
            // Preserve the gateBlocked progress event the blocking JSON path used
            // to emit before this preflight extraction.
            if case .handoverBlocked(let dangerClass, _, let reason, _) = error {
                let roundNumber = (loaded?.rounds.count ?? 0) + 1
                events?(.gateBlocked(round: roundNumber, dangerClass: dangerClass, reason: reason))
            }
            return .failure(error)
        case .success(let ok):
            state = ok.state
            extraction = ok.extraction
        }

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
            // Preflight already guaranteed non-empty handover + cleared HandoverGate.
            guard let handover = extraction.verdict.handover,
                  !handover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.verdictUnparseable(.continueWithoutHandover))
            }
            let gateDecision = HandoverGate.evaluate(handoverText: handover)

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

            let devDisplayName = await runService.workerDisplayName(forModelId: state.devModelId)
            let devRequest = RunRequest(
                message: RelayDevPrompt.assemble(context: .init(
                    handover: handover, docPath: state.docPath, roundNumber: roundNumber,
                    workerDisplayName: devDisplayName)),
                repoRoot: state.projectRoot, projectId: projectId,
                presetId: "build_slice", pinnedModelId: state.devModelId
            )
            // No `--until` in Pilot — `dispatchTurn` only needs `config` for its
            // deadline plumbing, which is always inert here (`until: nil`).
            let dispatchConfig = Config(
                projectRoot: state.projectRoot, projectId: projectId, docPath: state.docPath,
                pmModelId: state.pmModelId, devModelId: state.devModelId,
                maxRounds: maxRounds, until: nil, stagnationRoundCap: stagnationCap,
                devTurnIdleTimeoutSeconds: state.pilotDevTurnIdleTimeoutSeconds
            )
            let devResult = await dispatchDevTurn(
                devRequest,
                config: dispatchConfig,
                relayId: state.id,
                deliveryGuard: .init(
                    projectRoot: state.projectRoot,
                    baselineHead: round.baselineHead ?? gitObserver.observe(rootPath: state.projectRoot).head ?? ""
                ),
                site: .pilotDevTurn
            )
            applyDevTurnEnd(
                &round,
                endReason: devResult.endReason,
                owner: devResult.owner,
                proofResults: devResult.proofResults,
                proofCommands: devResult.proofCommands,
                writeScope: devResult.writeScope,
                scopeViolation: devResult.scopeViolation,
                standingFailed: devResult.standingFailed
            )
            // Reload laneBlocked (if any) written during harness wait.
            if let fresh = try? stateStore.load(id: state.id) {
                state.laneBlocked = fresh.laneBlocked
            }

            switch devResult.dispatch {
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
                escalate(&state, note: Self.serviceErrorEscalateNote(error, turn: "dev"))
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
                // PO-S04: proofTimeout / laneBusy during harness proof still delivered
                // the report, but the stamped endReason names what the harness did.
                if devResult.endReason == .laneBusy {
                    round.outcome = .escalated
                    round.finishedAt = now()
                    state.rounds[state.rounds.count - 1] = round
                    escalate(&state, note: "harness proof blocked on execution lane (round \(roundNumber))")
                    events?(.escalated(note: state.note ?? ""))
                    return .success(PilotRoundResult(state: state, devReport: devOutput))
                }
                // PO-S06/F4: scopeViolation / standingFailed keep endReason=reported;
                // work is rejected on the wire for the PM — no auto-revert. Stay
                // awaitingPM so the pilot PM can decide.
                round.outcome = .continued
                round.finishedAt = now()
                state.rounds[state.rounds.count - 1] = round
                state.laneBlocked = nil
                // Back to parked — the piloting session reviews the dev report and
                // calls `pilot handoff` again when ready. No clock, no auto-advance.
                state.status = .awaitingPM
                persistPMBoundary(state)
                events?(.devTurnFinished(round: roundNumber))
                return .success(PilotRoundResult(state: state, devReport: devOutput))
            }
        }
    }

    // MARK: - Adopt (docs/phases/Pilot_Relay.md §5, PL-S06) — adopt (unattended handover)

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
        /// RSC-S01: another process currently holds this relay's `RelayDispatchLock` —
        /// a concurrent `adopt`/`resume` is already mid read-check-write. Distinct from
        /// `.notAdoptable(status: "running")`, which means the durable state itself is
        /// already `.running`; this means the lock couldn't even be taken to check.
        case roundInFlight
        /// The durable claim write (`stateStore.save`) failed after eligibility passed.
        case journalUnavailable
    }

    /// `alln pair relay adopt --relay <id> --pm-model <id>` (`docs/phases/
    /// Pilot_Relay.md` §5 "adopt (unattended handover) is the strategic unlock") —
    /// converts a PARKED pilot relay (`pmMode == .external`, `status == .awaitingPM`
    /// or `.escalated`) to `pmMode: .spawned` with `pmModelId` as the new PM seat,
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
    /// RSC-HF (`--no-wait`): the guard-only half of `adopt` below — same
    /// lock/load/check/flip/persist/release discipline, minus the round loop. Returns
    /// the flipped state, the resolved config, and the one-time `adoptionNote` (it is
    /// NOT persisted onto `RelayState` — see `adopt`'s doc comment). `adopt` is built
    /// on top of this so there is exactly one guard implementation.
    public func adoptGuard(
        relayId: String, pmModelId: String, config: Config
    ) -> Result<(state: RelayState, config: Config, adoptionNote: String), AdoptError> {
        // RSC-S01: the lock covers ONLY the read-check-write window below — released
        // (by dropping this handle) right before the round loop, never held across it.
        // A crashed holder never wedges the relay: `flock` is released by the kernel on
        // process death, and liveness after the flip to `.running` is separately owned
        // by `owner.pid` + `reconcileOrphan` (unchanged).
        var lockHandle: ThreadFlockLock.Handle? = RelayDispatchLock.tryAcquire(
            relayId: relayId, relaysRoot: stateStore.rootDirectory
        )
        guard lockHandle != nil else { return .failure(.roundInFlight) }

        guard var state = stateStore.load(id: relayId) else {
            lockHandle = nil
            return .failure(.relayNotFound)
        }
        guard state.pmMode == .external else {
            lockHandle = nil
            return .failure(.notPilotRelay)
        }
        guard state.status == .awaitingPM || state.status == .escalated else {
            lockHandle = nil
            return .failure(.notAdoptable(status: state.status.rawValue))
        }

        let priorEscalationNote = state.status == .escalated ? state.note : nil
        let note = Self.adoptionNoteText(roundsSoFar: state.rounds.count, priorEscalationNote: priorEscalationNote)

        state.pmMode = .spawned
        state.pmModelId = pmModelId
        state.status = .running
        state.finishedAt = nil

        var adoptedConfig = config
        adoptedConfig.projectRoot = state.projectRoot
        adoptedConfig.docPath = state.docPath
        adoptedConfig.pmModelId = pmModelId
        adoptedConfig.devModelId = state.devModelId

        threadProjector?.started(state: state, projectId: config.projectId)
        do {
            try persistClaim(state)
        } catch {
            lockHandle = nil
            return .failure(.journalUnavailable)
        }
        lockHandle = nil

        return .success((state, adoptedConfig, note))
    }

    public func adopt(
        relayId: String, pmModelId: String, config: Config, events: EventSink? = nil
    ) async -> Result<RelayState, AdoptError> {
        switch adoptGuard(relayId: relayId, pmModelId: pmModelId, config: config) {
        case .failure(let error):
            return .failure(error)
        case .success(let (flipped, adoptedConfig, note)):
            var state = flipped
            await loop(state: &state, config: adoptedConfig, events: events, adoptionNote: note)
            return .success(state)
        }
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
    /// `pmModelId: RelayState.externalPMModelId` and persists — the round log and
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
        state.pmModelId = RelayState.externalPMModelId
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
    /// a resume can never silently redirect a relay at a different doc or repo. Fails with
    /// `.relayNotFound` when no such relay exists, `.notResumable(status:)` when its status
    /// isn't resumable (`.done`, or a ceiling-fired `.stopped` — a deliberate stop, never
    /// silently resumable), or `.roundInFlight` (RSC-S01) when another process already
    /// holds this relay's dispatch lock — the caller (CLI/MCP/GUI) turns any of these into
    /// a clean, honest error rather than the coordinator guessing.
    public enum DispatchRefusal: Swift.Error, Sendable, Equatable {
        case relayNotFound
        case notResumable(status: String)
        /// RSC-S01: another process currently holds this relay's `RelayDispatchLock` —
        /// a concurrent `resume`/`adopt` is already mid read-check-write.
        case roundInFlight
        /// RSC-S02: `run`'s start-time duplicate guard — a live-owner `.running` relay
        /// already exists on the same normalized `projectRoot` + `docPath`. Names the
        /// existing relay id so the caller can resume/adopt/inspect it instead of
        /// guessing. A dead-owner `.running` relay (orphan) never produces this — see
        /// `preflightStart`.
        case alreadyActive(relayId: String)
        /// The durable claim write (`stateStore.save`) failed after eligibility passed.
        case journalUnavailable
    }

    /// RSC-HF (`--no-wait`): the guard-only half of `resume` below — load, reconcile
    /// an orphan if needed, check eligibility, take the per-id dispatch lock, flip to
    /// `.running`, persist, release the lock. Returns the flipped state and the
    /// resolved config (worker ids / `projectRoot` / `docPath` taken from the loaded
    /// state, never from the caller-supplied `config`, exactly like `resume`) so a
    /// detached-dispatch caller can hand the round loop to a child process instead of
    /// running it in this one. `resume` is built on top of this so there is exactly
    /// one guard implementation — this is the same mutate-under-lock step either way,
    /// not a second, weaker check.
    public func resumeGuard(
        relayId: String, founderAnswer: String, config: Config
    ) -> Result<(state: RelayState, config: Config), DispatchRefusal> {
        // RSC-S01: same lock/window discipline as `adoptGuard` below — see its comment.
        var lockHandle: ThreadFlockLock.Handle? = RelayDispatchLock.tryAcquire(
            relayId: relayId, relaysRoot: stateStore.rootDirectory
        )
        guard lockHandle != nil else { return .failure(.roundInFlight) }

        guard let loaded = stateStore.load(id: relayId) else {
            lockHandle = nil
            return .failure(.relayNotFound)
        }
        var state = reconcileIfOrphaned(loaded)
        guard state.isResumable else {
            lockHandle = nil
            return .failure(.notResumable(status: state.status.rawValue))
        }
        var resumedConfig = config
        resumedConfig.projectRoot = state.projectRoot
        resumedConfig.docPath = state.docPath
        resumedConfig.pmModelId = state.pmModelId
        resumedConfig.devModelId = state.devModelId

        state.founderNote = founderAnswer
        state.status = .running
        state.finishedAt = nil
        // Re-affirms the thread's projectId (a no-op when already bound) and guarantees
        // the thread exists even if the original `run()` call never had a projector
        // attached — `sync` below is then guaranteed a thread to project onto.
        threadProjector?.started(state: state, projectId: config.projectId)
        do {
            try persistClaim(state)
        } catch {
            lockHandle = nil
            return .failure(.journalUnavailable)
        }
        lockHandle = nil

        return .success((state, resumedConfig))
    }

    public func resume(
        relayId: String, founderAnswer: String, config: Config, events: EventSink? = nil
    ) async -> Result<RelayState, DispatchRefusal> {
        switch resumeGuard(relayId: relayId, founderAnswer: founderAnswer, config: config) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(let (flipped, resumedConfig)):
            var state = flipped
            await loop(state: &state, config: resumedConfig, events: events)
            return .success(state)
        }
    }

    /// `pair relay-status` / MCP `pair_relay(action: status)` — the read path that also
    /// reconciles (works-test hazard #1: "on load/list/status/start"). Returns `nil` only
    /// when no such relay exists.
    public func status(relayId: String) -> RelayState? {
        guard let state = stateStore.load(id: relayId) else { return nil }
        return reconcileIfOrphaned(state)
    }

    // MARK: - Founder stop (ATL-S02 / docs/phases/Agent_Team_Loop.md §Stop settlement)

    /// `pair relay stop` failure. Never maps escalated abandon to invalid-state —
    /// stop is allowed on `escalated`/`awaitingPM`/`running`. `RELAY_ROUND_IN_FLIGHT`
    /// is a start/resume/adopt guard only; stop never returns it.
    public enum StopRefusal: Swift.Error, Sendable, Equatable {
        case relayNotFound
        /// Could not honestly settle: a signalled owner/turn tree is still
        /// identity-alive (or legacy `owner.pid` still alive). State left non-terminal.
        case stopFailed(detail: String)
    }

    /// Founder abandonment of a Loop (`pair relay stop`). Follows the packet's
    /// exact ten-step settlement order. Reuses Process Ownership identity-checked
    /// terminate helpers inside this path — never calls `ProcessOwnershipSurface.kill`
    /// as the whole product path (that path lacks PM Turn + founder reason + escalated abandon).
    public func stop(
        relayId: String,
        reason: String = RelayState.founderStoppedReason
    ) -> Result<RelayState, StopRefusal> {
        // Prefer the per-id dispatch flock so stop cannot race a concurrent
        // resume/adopt claim. Blocking acquire: stop must win over in-flight
        // dispatch, not refuse with RELAY_ROUND_IN_FLIGHT.
        let lockURL = RelayDispatchLock.lockURL(relayId: relayId, relaysRoot: stateStore.rootDirectory)
        var lockHandle: ThreadFlockLock.Handle?
        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            lockHandle = try ThreadFlockLock.acquire(lockURL: lockURL)
        } catch {
            // Directory/lock failure is not a stop refusal by itself — proceed;
            // identity-checked settlement still runs, and persist will fail loud if needed.
            lockHandle = nil
        }
        defer { lockHandle = nil }

        // 1. Load durable state.
        guard let loaded = stateStore.load(id: relayId) else {
            return .failure(.relayNotFound)
        }

        // 2. Already terminal → idempotent success (no kill storm, no second PM Turn).
        switch loaded.status {
        case .done, .stopped:
            return .success(loaded)
        case .running, .escalated, .awaitingPM:
            break
        }

        var state = loaded
        let relayDir = try? stateStore.directory(for: state.id)
        var turnWasSignalled = false

        // 3. Signal relay owner process (identity-checked when owner.json exists;
        //    legacy owner.pid is a raw-pid marker — never invent a full identity).
        if let relayDir {
            if let ownerIdentity = ProcessOwnership.readOwnerIdentity(in: relayDir) {
                if ProcessOwnership.isIdentityAlive(ownerIdentity) {
                    _ = ProcessOwnership.terminateOwnerIdentityIfSafe(ownerIdentity)
                    if ProcessOwnership.isIdentityAlive(ownerIdentity) {
                        return .failure(.stopFailed(
                            detail: "relay owner identity still alive after signal"
                        ))
                    }
                }
            } else if !stateStore.isOwnerDead(id: state.id) {
                // Legacy owner.pid: best-effort TERM→grace→KILL on the recorded pid
                // when it is not this process (stop is called from a separate CLI).
                if let rawPid = Self.readLegacyOwnerPid(in: relayDir),
                   rawPid > 0,
                   rawPid != ProcessInfo.processInfo.processIdentifier {
                    _ = kill(rawPid, SIGTERM)
                    usleep(ProcessOwnership.processGroupKillGraceMicroseconds)
                    if ProcessOwnership.processAlive(rawPid) {
                        _ = kill(rawPid, SIGKILL)
                        usleep(50_000)
                    }
                    if ProcessOwnership.processAlive(rawPid) {
                        return .failure(.stopFailed(
                            detail: "relay owner.pid still alive after signal"
                        ))
                    }
                }
            }
        }

        // 4. Signal in-flight turn trees (turn-owner file, then last-round owner).
        if let relayDir {
            if let turnOwner = ProcessOwnership.readTurnOwner(in: relayDir) {
                if ProcessOwnership.isIdentityAlive(turnOwner) {
                    let signalled = ProcessOwnership.terminateOwnerIdentityIfSafe(turnOwner)
                    turnWasSignalled = signalled || turnWasSignalled
                    if ProcessOwnership.isIdentityAlive(turnOwner) {
                        return .failure(.stopFailed(
                            detail: "dev-turn owner identity still alive after signal"
                        ))
                    }
                } else {
                    // Dead but present: still count as a turn that needs endReason=killed.
                    turnWasSignalled = true
                }
            } else if let lastIndex = state.rounds.indices.last,
                      let record = state.rounds[lastIndex].devTurnOwner,
                      let identity = ProcessOwnership.OwnerIdentity.fromRecord(record) {
                if ProcessOwnership.isIdentityAlive(identity) {
                    let signalled = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
                    turnWasSignalled = signalled || turnWasSignalled
                    if ProcessOwnership.isIdentityAlive(identity) {
                        return .failure(.stopFailed(
                            detail: "last-round turn owner identity still alive after signal"
                        ))
                    }
                }
            }
        }

        // 5. Clear turn-owner file + laneBlocked.
        if let relayDir {
            ProcessOwnership.clearTurnOwner(in: relayDir)
        }
        state.laneBlocked = nil

        // 6. Stamp round in flight if open.
        if let lastIndex = state.rounds.indices.last {
            if state.rounds[lastIndex].outcome == nil {
                state.rounds[lastIndex].outcome = .stopped
                state.rounds[lastIndex].finishedAt = now()
            }
            if turnWasSignalled, state.rounds[lastIndex].devTurnEndReason == nil {
                state.rounds[lastIndex].devTurnEndReason = .killed
            }
        }

        // 7. Stamp relay founder stop (transitioning only — never overwrites terminal).
        state.status = .stopped
        state.stoppedReason = reason
        state.finishedAt = now()

        // 8–9. Write PM Turn via the same persistPMBoundary path as ceiling stop,
        // then persist state + threadProjector.sync.
        persistPMBoundary(state)

        // 10. Return projected state.
        return .success(state)
    }

    /// Reads the legacy raw-pid marker under a relay directory. Never a full identity.
    private static func readLegacyOwnerPid(in directory: URL) -> Int32? {
        let url = directory.appendingPathComponent("owner.pid")
        guard let raw = try? String(contentsOf: url, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
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

        // PO-S02: identity-checked group-kill of any in-flight dev-turn worker tree
        // before settling the round. Prefer the durable turn-owner file; fall back
        // to the last round's recorded owner. Same kill function as live turn-end.
        if let relayDir = try? stateStore.directory(for: reconciled.id) {
            if let turnOwner = ProcessOwnership.readTurnOwner(in: relayDir) {
                _ = ProcessOwnership.terminateOwnerIdentityIfSafe(turnOwner)
                ProcessOwnership.clearTurnOwner(in: relayDir)
                if let lastIndex = reconciled.rounds.indices.last,
                   reconciled.rounds[lastIndex].devTurnEndReason == nil {
                    reconciled.rounds[lastIndex].devTurnOwner =
                        reconciled.rounds[lastIndex].devTurnOwner ?? turnOwner.asRecord()
                    // Actor ending the turn is reconcile — stamp killed, never infer.
                    reconciled.rounds[lastIndex].devTurnEndReason = .killed
                }
            } else if let lastIndex = reconciled.rounds.indices.last,
                      let record = reconciled.rounds[lastIndex].devTurnOwner,
                      let identity = ProcessOwnership.OwnerIdentity.fromRecord(record) {
                _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
                if reconciled.rounds[lastIndex].devTurnEndReason == nil {
                    reconciled.rounds[lastIndex].devTurnEndReason = .killed
                }
            }
        }

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
        let kickoffMessage = state.kickoffMessage
        let pmContext = RelayPMPrompt.Context(
            docPath: config.docPath,
            roundNumber: roundNumber,
            baselineHead: previousRound?.baselineHead ?? baselineHead ?? "",
            currentHead: previousRound?.headAfterDev,
            devReport: devReport,
            founderNote: founderNote,
            adoptionNote: adoptionNote,
            kickoffMessage: kickoffMessage,
            maxRounds: config.maxRounds,
            roundsRemaining: max(0, config.maxRounds - roundNumber + 1)
        )
        if founderNote != nil {
            // One-time injection into "the next PM turn" (brief) — never restated.
            state.founderNote = nil
            persist(state)
        }
        if kickoffMessage != nil {
            // ATL-S01: consume-once after first PM assemble — later rounds never re-inject.
            state.kickoffMessage = nil
            persist(state)
        }

        let pmRequest = RunRequest(
            message: RelayPMPrompt.assemble(context: pmContext),
            repoRoot: config.projectRoot, projectId: config.projectId,
            presetId: config.presetId, pinnedModelId: config.pmModelId
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
                escalate(&$0, note: Self.serviceErrorEscalateNote(error, turn: "PM"))
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
                presetId: config.presetId, pinnedModelId: config.pmModelId
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
                    escalate(&$0, note: Self.serviceErrorEscalateNote(error, turn: "PM re-ask"))
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

            let devDisplayName = await runService.workerDisplayName(forModelId: config.devModelId)
            let devRequest = RunRequest(
                message: RelayDevPrompt.assemble(context: .init(
                    handover: handover, docPath: config.docPath, roundNumber: roundNumber,
                    workerDisplayName: devDisplayName)),
                repoRoot: config.projectRoot, projectId: config.projectId,
                presetId: config.presetId, pinnedModelId: config.devModelId
            )
            let devResult = await dispatchDevTurn(
                devRequest,
                config: config,
                relayId: state.id,
                deliveryGuard: .init(
                    projectRoot: config.projectRoot,
                    baselineHead: round.baselineHead ?? baselineHead ?? ""
                ),
                site: .relayDevTurn
            )
            applyDevTurnEnd(
                &round,
                endReason: devResult.endReason,
                owner: devResult.owner,
                proofResults: devResult.proofResults,
                proofCommands: devResult.proofCommands,
                writeScope: devResult.writeScope,
                scopeViolation: devResult.scopeViolation,
                standingFailed: devResult.standingFailed
            )
            if let fresh = try? stateStore.load(id: state.id) {
                state.laneBlocked = fresh.laneBlocked
            }
            switch devResult.dispatch {
            case .deadline:
                return finishRound(&state, &round, outcome: .stopped, events: events) {
                    stop(&$0, reason: "--until deadline reached during the dev turn (round \(roundNumber))")
                    events?(.stopped(reason: $0.stoppedReason ?? ""))
                }
            case .serviceError(let error):
                return finishRound(&state, &round, outcome: .escalated, events: events) {
                    escalate(&$0, note: Self.serviceErrorEscalateNote(error, turn: "dev"))
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
                if devResult.endReason == .laneBusy {
                    return finishRound(&state, &round, outcome: .escalated, events: events) {
                        escalate(&$0, note: "harness proof blocked on execution lane (round \(roundNumber))")
                        events?(.escalated(note: $0.note ?? ""))
                    }
                }
                // PO-S06/F4: scopeViolation / standingFailed surface on roundLog;
                // endReason stays reported; continue so the PM sees the rejection
                // and decides (no auto-revert / auto-regen / auto-commit).
                round.outcome = .continued
                round.finishedAt = now()
                state.laneBlocked = nil
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

    private struct TurnDeliveryGuard: Sendable {
        var projectRoot: String
        var baselineHead: String
    }

    /// Result of a **dev** turn dispatch: the turn outcome plus the stamped endReason
    /// and last recorded process-group owner (PO-S02), plus PO-S04 harness proofs,
    /// PO-S06 write-scope declaration / fail-closed violation, and PO-F4 standing
    /// invariant failures.
    private struct DevTurnDispatch {
        var dispatch: TurnDispatch
        var endReason: DevTurnEndReason
        var owner: ProcessOwnerRecord?
        var proofResults: [HarnessProofResult] = []
        var proofCommands: [String] = []
        var writeScope: TurnWriteScope? = nil
        var scopeViolation: ScopeViolation? = nil
        /// PO-F4: non-nil when one or more standing invariants failed.
        var standingFailed: [String]? = nil
    }

    private static let partialCompletionRetryHint =
        "A prior attempt may have partially completed; verify existing state before redoing work."

    /// Dispatches ONE turn through `RunService`, retrying on `.stalled`/`.emptyResult`/
    /// `.infraBackoff`/`.compacting` per `RelayTurnClassifier.RetryCeiling` (a bare retry —
    /// simpler than `PairCoordinator`'s nudge-prompt retries, since the relay's retries are
    /// for infra hiccups/compaction/hangs, not "your check failed, try differently"; the PM
    /// or dev's own free prose already carries anything it needs to try differently).
    /// `--until` is honored between attempts (mirrors QUEUE-S02).
    ///
    /// When `deliveryGuard` is set (mutating dev turns), a stall/empty retry first re-observes
    /// HEAD: if it moved past the turn baseline, classify delivered-not-stalled instead of
    /// re-dispatching (FR9). Ambiguous cases (output but no commit) append one retry hint.
    private func dispatchTurn(
        _ request: RunRequest,
        config: Config,
        deliveryGuard: TurnDeliveryGuard? = nil
    ) async -> TurnDispatch {
        var request = request
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
            let outcome = run.answers.first?.result
                ?? WorkerRunOutcome(status: .failed, errorReason: "no worker answer")

            switch RelayTurnClassifier.classify(.init(outcome: outcome)) {
            case .delivered(let text):
                return .delivered(run, text)
            case .stalled:
                if let delivered = deliveredDespiteStallSignal(
                    run: run, outcome: outcome, request: &request, deliveryGuard: deliveryGuard
                ) { return delivered }
                stalledAttempts += 1
                if stalledAttempts > RelayTurnClassifier.RetryCeiling.maxStalledAttempts {
                    return .budgetExhausted("stalled repeatedly (\(stalledAttempts) attempts)")
                }
            case .emptyResult:
                if let delivered = deliveredDespiteStallSignal(
                    run: run, outcome: outcome, request: &request, deliveryGuard: deliveryGuard
                ) { return delivered }
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

    /// PO-S02 + PO-S03 + PO-S04 + PO-S06 dev-turn dispatch: acquires the per-root
    /// execution lane for the turn duration (FIFO ticket when busy; scoped docs-only
    /// turns may co-hold when write scopes are disjoint). Every attempt and terminal
    /// path still routes through identity-checked group kill and stamps a
    /// `DevTurnEndReason`. After a delivered turn, the harness runs declared
    /// `proofCommands` and fail-closed write-scope commit-diff enforcement.
    /// SR-10 (Sol F11) + PLS-S02: durably stamp the dev run id on the open round as
    /// soon as dispatch starts (before the long worker wait) and again before harness
    /// proof. If the coordinator dies mid-turn, `pilot status` can still read stream
    /// liveness from the linked journal instead of falling back to relay heartbeat.
    private func persistDeliveredDevRun(relayId: String, runId: String, rootPath: String) {
        guard var state = stateStore.load(id: relayId), !state.rounds.isEmpty else { return }
        var round = state.rounds[state.rounds.count - 1]
        if round.devRunId == nil { round.devRunId = runId }
        if round.headAfterDev == nil {
            round.headAfterDev = gitObserver.observe(rootPath: rootPath).head
        }
        state.rounds[state.rounds.count - 1] = round
        try? stateStore.save(state)
    }

    private func dispatchDevTurn(
        _ request: RunRequest,
        config: Config,
        relayId: String,
        deliveryGuard: TurnDeliveryGuard? = nil,
        site: ExecutionLaneSite = .relayDevTurn,
        turnStateProofCommands: [String] = [],
        turnStateWriteScope: TurnWriteScope? = nil
    ) async -> DevTurnDispatch {
        let relayDir = try? stateStore.directory(for: relayId)
        if let relayDir {
            ProcessOwnership.TurnOwnerDirectory.shared.set(relayDir)
        }
        defer {
            ProcessOwnership.TurnOwnerDirectory.shared.set(nil)
        }

        // PO-S03: build-class site must take the lane; panels never call here.
        // PO-S06: docs-only still uses the lane for scope coordination (not panel).
        precondition(
            ExecutionLaneClassification.mustAcquire(site)
                || site == .relayDevTurn
                || site == .pilotDevTurn,
            "dispatchDevTurn is relay/pilot only; panel seats must not acquire the lane"
        )

        // PO-F10: explicit --dev-model must resolve BEFORE lane wait / stall-retry.
        // An unresolvable worker escalates with AGENT_NOT_AVAILABLE — never 4 silent stalls.
        if let modelId = request.pinnedModelId, !modelId.isEmpty {
            if case .failure(let error) = await runService.resolveExplicitModel(modelId) {
                return DevTurnDispatch(
                    dispatch: .serviceError(error),
                    endReason: .unknown,
                    owner: nil,
                    writeScope: turnStateWriteScope
                )
            }
        }

        // PO-S06: scope must be known before acquire (concurrency). Prefer turn-state,
        // else parse the handover/message (PM can declare writeScope up front), else
        // legacy full-build. Report-tail re-parse after delivery is fail-closed only.
        let acquireScope = turnStateWriteScope
            ?? TurnWriteScopeParser.parse(from: request.message)
            ?? .legacyFullBuild

        let laneKey = ExecutionLane.key(repoRoot: config.projectRoot)
        let claimKind = site.rawValue
        let claim = ExecutionLane.Claim.current(
            id: relayId, kind: claimKind, writeScope: acquireScope
        ) ?? ExecutionLane.Claim(
            id: relayId,
            kind: claimKind,
            identity: ProcessOwnership.OwnerIdentity(
                pid: ProcessInfo.processInfo.processIdentifier,
                pgid: nil,
                startTimeTicks: 0,
                kind: .inProcess
            ),
            writeScope: acquireScope
        )

        let store = stateStore
        let onTicket: @Sendable (ExecutionLaneTicket) -> Void = { ticket in
            guard var state = try? store.load(id: relayId) else { return }
            state.laneBlocked = ticket
            try? store.save(state)
        }
        let clearBlocked: @Sendable () -> Void = {
            guard var state = try? store.load(id: relayId) else { return }
            state.laneBlocked = nil
            try? store.save(state)
        }

        // Harness-owned wait: surface FIFO ticket on status; agents must not busy-loop.
        // Mutable so the proof phase can release the turn hold and re-acquire as harnessProof.
        var laneToken = await executionLane.waitToAcquire(
            laneKey,
            claim: claim,
            timeout: config.executionLaneWaitTimeout,
            now: now,
            onTicket: onTicket
        )
        defer {
            clearBlocked()
            if let token = laneToken {
                Task { await executionLane.release(laneKey, token: token, endReason: "completed") }
            }
        }
        guard laneToken != nil else {
            clearBlocked()
            // Still blocked after wait bound — typed lane busy, no worker spawn.
            if let ticket = await executionLane.currentTicket(
                laneKey, now: now(), forClaim: claim
            ) {
                onTicket(ticket)
            }
            return DevTurnDispatch(
                dispatch: .serviceError(.executionLaneBusy(config.projectRoot)),
                endReason: .laneBusy,
                owner: nil,
                writeScope: turnStateWriteScope
            )
        }
        // Clear ticket once we hold the lane (wait path may have left the last ticket).
        clearBlocked()

        var request = request
        // PO-F7: dev-turn idle-timeout override (reuses PO-F5's RunRequest field).
        request.workerTimeoutSeconds = config.devTurnIdleTimeoutSeconds
        var stalledAttempts = 0
        var emptyAttempts = 0
        var infraAttempts = 0
        var compactionAttempts = 0
        var lastOwner: ProcessOwnerRecord?

        func captureOwner() {
            if let relayDir, let identity = ProcessOwnership.readTurnOwner(in: relayDir) {
                lastOwner = identity.asRecord()
            }
        }

        /// ONE kill path for every turn-end / retry (identity-checked group kill).
        func killTurnGroup() {
            captureOwner()
            if let relayDir {
                _ = ProcessOwnership.terminateTurnOwnerIfSafe(in: relayDir)
            } else if let record = lastOwner,
                      let identity = ProcessOwnership.OwnerIdentity.fromRecord(record) {
                _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
            }
        }

        /// PO-S06: resolve declared scope from turn state / report and fail-closed
        /// diff baseline..HEAD against path prefixes. Never reverts commits.
        func evaluateWriteScope(
            report: String?,
            baselineHead: String?
        ) -> (scope: TurnWriteScope, violation: ScopeViolation?) {
            let scope = TurnWriteScopeParser.resolve(
                turnState: turnStateWriteScope, report: report
            )
            // Undeclared / no prefixes → no fail-closed check (legacy).
            guard scope.hasDeclaredPrefixes else {
                return (scope, nil)
            }
            let head = gitObserver.observe(rootPath: config.projectRoot).head
            guard let baselineHead, let head, baselineHead != head else {
                return (scope, nil)
            }
            let changed = gitObserver.changedFilesInRange(
                rootPath: config.projectRoot, baseline: baselineHead, head: head
            )
            let outOfScope = scope.outOfScopePaths(in: changed)
            guard !outOfScope.isEmpty else { return (scope, nil) }
            return (
                scope,
                ScopeViolation(
                    declaredScope: scope.pathPrefixes,
                    outOfScopePaths: outOfScope
                )
            )
        }

        /// PO-S04: after the agent turn ends, the harness runs proof of record.
        /// Releases the dev-turn lane hold and re-acquires as `harnessProof` so a
        /// foreign holder can surface `laneBusy` on the proof path (works test).
        /// PO-S06: also stamps writeScope + scopeViolation (endReason stays reported).
        /// PO-F4: always runs standing invariants (even when `proofCommands` is empty);
        /// failures surface as `standingFailed` without rewriting endReason.
        func finishWithHarnessProof(
            dispatch: TurnDispatch,
            report: String?,
            baseEndReason: DevTurnEndReason
        ) async -> DevTurnDispatch {
            // SR-10 (Sol F11): make the delivered dev run recoverable across a crash during
            // the proof phase by persisting its id + resulting HEAD to the round now, before
            // any (slow) proof commands run.
            if case .delivered(let deliveredRun, _) = dispatch {
                persistDeliveredDevRun(
                    relayId: relayId, runId: deliveredRun.id, rootPath: config.projectRoot
                )
            }
            let baseline = deliveryGuard?.baselineHead
            let (resolvedScope, violation) = evaluateWriteScope(
                report: report, baselineHead: baseline
            )
            // Surface declaration even when it matches legacy defaults only if
            // turn-state/report actually declared something.
            let declared: TurnWriteScope? = {
                if turnStateWriteScope != nil { return resolvedScope }
                if TurnWriteScopeParser.parse(from: report ?? "") != nil { return resolvedScope }
                return nil
            }()

            let commands = HarnessProofCommandsParser.resolve(
                turnState: turnStateProofCommands,
                report: report
            )

            // Agent group is already dead (caller killed). Clear turn-owner dir before
            // proof / standing-invariant spawns so harnessProof children do not
            // overwrite turn-owner identity.
            ProcessOwnership.TurnOwnerDirectory.shared.set(nil)

            // Release turn hold so the proof phase takes the lane as harnessProof.
            if let token = laneToken {
                await executionLane.release(laneKey, token: token, endReason: "devTurnCompleted")
                laneToken = nil
            }

            // Harness proof is always build-class (full exclusive) — legacy claim.
            let proofClaim = ExecutionLane.Claim.current(
                id: "\(relayId):proof",
                kind: ExecutionLaneSite.harnessProof.rawValue,
                writeScope: .legacyFullBuild
            ) ?? ExecutionLane.Claim(
                id: "\(relayId):proof",
                kind: ExecutionLaneSite.harnessProof.rawValue,
                identity: ProcessOwnership.OwnerIdentity(
                    pid: ProcessInfo.processInfo.processIdentifier,
                    pgid: nil,
                    startTimeTicks: 0,
                    kind: .inProcess
                ),
                writeScope: .legacyFullBuild
            )
            let proofToken = await executionLane.waitToAcquire(
                laneKey,
                claim: proofClaim,
                timeout: config.proofLaneWaitTimeout,
                now: now,
                onTicket: onTicket
            )
            laneToken = proofToken
            guard proofToken != nil else {
                clearBlocked()
                if let ticket = await executionLane.currentTicket(
                    laneKey, now: now(), forClaim: proofClaim
                ) {
                    onTicket(ticket)
                }
                return DevTurnDispatch(
                    dispatch: dispatch,
                    endReason: .laneBusy,
                    owner: lastOwner,
                    proofResults: [],
                    proofCommands: commands,
                    writeScope: declared,
                    scopeViolation: violation
                )
            }
            clearBlocked()

            let scratch = ExecutionLaneFlock.ensuredScratchPath(repoRoot: config.projectRoot)
            let service = ProjectVerificationService(
                commandRunner: proofCommandRunner,
                perCommandTimeoutSeconds: config.proofTimeoutSeconds,
                now: now
            )

            // Declared proofs (opt-in) — may be empty.
            var results: [HarnessProofResult] = []
            if !commands.isEmpty {
                results = await service.runProofs(
                    commands: commands,
                    repoRoot: config.projectRoot,
                    scratchPath: scratch
                )
            }

            // PO-F4: standing invariants — always, not opt-in. Use the turn tree's
            // built alln on the persistent scratch (never global/installed alln).
            let standing = await StandingInvariants.run(
                service: service,
                repoRoot: config.projectRoot,
                scratchPath: scratch
            )
            results.append(contentsOf: standing.results)
            let standingFailed: [String]? = standing.failed.isEmpty ? nil : standing.failed

            // Only declared-proof timeouts rewrite endReason; standing failures leave
            // it as reported (analogous to scopeViolation).
            let declaredTimedOut = results.contains { !$0.standing && $0.timedOut }
            return DevTurnDispatch(
                dispatch: dispatch,
                endReason: declaredTimedOut ? .proofTimeout : baseEndReason,
                owner: lastOwner,
                proofResults: results,
                proofCommands: commands,
                writeScope: declared,
                scopeViolation: violation,
                standingFailed: standingFailed
            )
        }

        while true {
            if isPastDeadline(config) {
                killTurnGroup()
                return DevTurnDispatch(dispatch: .deadline, endReason: .killed, owner: lastOwner)
            }

            let attemptRunId = RunService.mintRunId()
            persistDeliveredDevRun(
                relayId: relayId, runId: attemptRunId, rootPath: config.projectRoot
            )
            let result = await runService.run(request, origin: .cli, runId: attemptRunId)
            captureOwner()

            guard case .success(let run) = result else {
                killTurnGroup()
                if case .failure(let error) = result {
                    return DevTurnDispatch(dispatch: .serviceError(error), endReason: .unknown, owner: lastOwner)
                }
                return DevTurnDispatch(
                    dispatch: .serviceError(.noWorker("relay turn dispatch failed")),
                    endReason: .unknown, owner: lastOwner
                )
            }
            let outcome = run.answers.first?.result
                ?? WorkerRunOutcome(status: .failed, errorReason: "no worker answer")

            switch RelayTurnClassifier.classify(.init(outcome: outcome)) {
            case .delivered(let text):
                // Reported success: reap agent group, then harness-owned proof of record.
                killTurnGroup()
                return await finishWithHarnessProof(
                    dispatch: .delivered(run, text),
                    report: text,
                    baseEndReason: .reported
                )
            case .stalled:
                if let delivered = deliveredDespiteStallSignal(
                    run: run, outcome: outcome, request: &request, deliveryGuard: deliveryGuard
                ) {
                    killTurnGroup()
                    let report: String?
                    if case .delivered(_, let t) = delivered { report = t } else { report = nil }
                    return await finishWithHarnessProof(
                        dispatch: delivered, report: report, baseEndReason: .reported
                    )
                }
                // Retry: kill this attempt's group before the next spawn.
                killTurnGroup()
                stalledAttempts += 1
                if stalledAttempts > RelayTurnClassifier.RetryCeiling.maxStalledAttempts {
                    return DevTurnDispatch(
                        dispatch: .budgetExhausted("stalled repeatedly (\(stalledAttempts) attempts)"),
                        endReason: .stalled, owner: lastOwner
                    )
                }
            case .emptyResult:
                if let delivered = deliveredDespiteStallSignal(
                    run: run, outcome: outcome, request: &request, deliveryGuard: deliveryGuard
                ) {
                    killTurnGroup()
                    let report: String?
                    if case .delivered(_, let t) = delivered { report = t } else { report = nil }
                    return await finishWithHarnessProof(
                        dispatch: delivered, report: report, baseEndReason: .reported
                    )
                }
                killTurnGroup()
                emptyAttempts += 1
                if emptyAttempts > RelayTurnClassifier.RetryCeiling.maxEmptyResultAttempts {
                    return DevTurnDispatch(
                        dispatch: .budgetExhausted("returned empty output repeatedly (\(emptyAttempts) attempts)"),
                        endReason: .stalled, owner: lastOwner
                    )
                }
            case .infraBackoff:
                killTurnGroup()
                infraAttempts += 1
                if infraAttempts > RelayTurnClassifier.RetryCeiling.maxInfraBackoffAttempts {
                    return DevTurnDispatch(
                        dispatch: .budgetExhausted("infra backoff budget exhausted (\(infraAttempts) attempts)"),
                        endReason: .stalled, owner: lastOwner
                    )
                }
                await sleepClampedToDeadline(config, seconds: RelayTurnClassifier.RetryCeiling.infraBackoffGraceSeconds)
            case .compacting:
                // Compaction is not a kill — leave the worker group alone and wait.
                compactionAttempts += 1
                if compactionAttempts > RelayTurnClassifier.RetryCeiling.maxCompactionAttempts {
                    killTurnGroup()
                    return DevTurnDispatch(
                        dispatch: .budgetExhausted("still compacting after \(compactionAttempts) retries"),
                        endReason: .stalled, owner: lastOwner
                    )
                }
                await sleepClampedToDeadline(config, seconds: RelayTurnClassifier.RetryCeiling.compactionGraceSeconds)
            }

            if isPastDeadline(config) {
                killTurnGroup()
                return DevTurnDispatch(dispatch: .deadline, endReason: .killed, owner: lastOwner)
            }
        }
    }

    /// Stamp PO-S02/S04/S06/F4 fields on the open round after a dev-turn dispatch settles.
    private func applyDevTurnEnd(
        _ round: inout RelayRound,
        endReason: DevTurnEndReason,
        owner: ProcessOwnerRecord?,
        proofResults: [HarnessProofResult] = [],
        proofCommands: [String] = [],
        writeScope: TurnWriteScope? = nil,
        scopeViolation: ScopeViolation? = nil,
        standingFailed: [String]? = nil
    ) {
        if round.devTurnEndReason == nil {
            round.devTurnEndReason = endReason
        }
        if let owner {
            round.devTurnOwner = owner
        }
        if !proofResults.isEmpty {
            round.proofResults = proofResults
        }
        if !proofCommands.isEmpty {
            round.proofCommands = proofCommands
        }
        if let writeScope {
            round.writeScope = writeScope
        }
        if let scopeViolation {
            round.scopeViolation = scopeViolation
        }
        if let standingFailed {
            round.standingFailed = standingFailed
        }
    }

    /// FR9 — before a mutating dev-turn stall/empty retry, re-observe HEAD; if the repo
    /// advanced past the turn baseline, treat the turn as delivered. Otherwise, when output
    /// exists but HEAD is unchanged, annotate the next retry prompt once.
    private func deliveredDespiteStallSignal(
        run: TeamRun,
        outcome: WorkerRunOutcome,
        request: inout RunRequest,
        deliveryGuard: TurnDeliveryGuard?
    ) -> TurnDispatch? {
        guard let deliveryGuard else { return nil }
        let head = gitObserver.observe(rootPath: deliveryGuard.projectRoot).head
        if head != deliveryGuard.baselineHead {
            let output = (outcome.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .delivered(run, output.isEmpty ? "(worker committed; settlement signal missed — repo advanced)" : output)
        }
        let visible = (outcome.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !visible.isEmpty && !request.message.contains(Self.partialCompletionRetryHint) {
            request.message += "\n\n" + Self.partialCompletionRetryHint
        }
        return nil
    }

    // MARK: - Small helpers

    /// Dev report for a settled round — the same `RunStore` lookup `runExternalRound`
    /// uses when building `PilotRoundResult.devReport` (`Pilot_DX.md` §DX5).
    public static func settledDevReport(for state: RelayState, runStore: RunStore = RunStore()) -> String? {
        guard let devRunId = state.rounds.last?.devRunId else { return nil }
        return runStore.load(runId: devRunId)?.answers.first?.output
    }

    private func devReportText(runId: String) -> String? {
        runStore.load(runId: runId)?.answers.first?.output
    }

    private func stop(_ state: inout RelayState, reason: String) {
        state.status = .stopped
        state.stoppedReason = reason
        state.finishedAt = now()
        persistPMBoundary(state)
    }

    private func escalate(_ state: inout RelayState, note: String) {
        state.status = .escalated
        state.note = note
        state.finishedAt = now()
        persistPMBoundary(state)
    }

    /// PO-F10: surface the typed error code (e.g. AGENT_NOT_AVAILABLE) in the
    /// escalation note so a failed explicit worker is never a silent stall.
    private static func serviceErrorEscalateNote(_ error: RunServiceError, turn: String) -> String {
        "\(error.code): \(turn) turn failed to dispatch: \(error.description)"
    }

    private func finish(_ state: inout RelayState, note: String?) {
        state.status = .done
        state.note = note
        state.finishedAt = now()
        persistPMBoundary(state)
    }

    /// PTD-1b write order: construct and atomically save the PM Turn before the
    /// relay's parked or terminal state is persisted. Receipt persistence is a required
    /// boundary invariant, so a failure stops instead of publishing an undeliverable
    /// relay state.
    private func persistPMBoundary(_ state: RelayState) {
        let report = Self.settledDevReport(for: state, runStore: runStore)
        do {
            try writePMTurn(
                for: state,
                reason: state.status.rawValue,
                report: report,
                nextCommands: pmTurnNextCommands(for: state)
            )
        } catch {
            preconditionFailure("failed to persist PM Turn for relay \(state.id): \(error)")
        }
        persist(state)
    }

    private func writePMTurn(
        for state: RelayState,
        reason: String,
        report: String?,
        nextCommands: [String]
    ) throws {
        let turn = PMTurnJSON(
            kind: .relay,
            subjectId: state.id,
            sequence: try pmTurnStore.nextSequence(for: .relay, subjectId: state.id),
            round: state.rounds.last?.roundNumber,
            createdAt: now(),
            reason: reason,
            lifecycleStatus: state.status.rawValue,
            report: report,
            workerRunId: state.rounds.last?.devRunId,
            workRecovery: nil,
            nextCommands: nextCommands,
            notes: report == nil ? ["settled_dev_report_missing"] : [],
            pmMode: state.pmMode.rawValue
        )
        try pmTurnStore.save(turn)
    }

    private func pmTurnNextCommands(for state: RelayState) -> [String] {
        let status = "alln pair relay-status --relay \(state.id) --json"
        guard state.status == .awaitingPM, state.pmMode == .external else {
            return [status]
        }
        return [
            "alln pair pilot handoff --relay \(state.id) --verdict continue --handover-file order.md --json",
            status
        ]
    }

    /// The single choke point every `RelayState` mutation already runs through — the
    /// natural, minimal-diff hook for `threadProjector?.sync` (R-S07): it fires
    /// synchronously right after each state change, so a round's escalation note is
    /// always captured before a LATER round could overwrite `state.note`.
    private func persist(_ state: RelayState) {
        try? stateStore.save(state)
        threadProjector?.sync(state: state, now: now())
    }

    /// Hard-fail claim persist for the first `.running` write in `run`/`resumeGuard`/
    /// `adoptGuard`. Mid-loop mutations keep using `persist(_:)` (`try?`) for now.
    private func persistClaim(_ state: RelayState) throws {
        try stateStore.save(state)
        threadProjector?.sync(state: state, now: now())
        DetachedHandoff.reportAccepted(id: state.id)
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
