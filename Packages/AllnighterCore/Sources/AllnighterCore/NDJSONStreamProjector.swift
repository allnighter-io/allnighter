import Foundation
import AgentOSTeam

/// Projects a settled `TeamRun` into the public NDJSON event sequence for
/// `alln team --stream` (docs/archive/phases/CLI_Implementation_Contract.md §NDJSON
/// Stream). Events are ordered by `seq`, carry the run's real timestamps, and the
/// final event is always a terminal one (`teamRunCompleted`/`teamRunFailed`).
///
/// This is a faithful event log derived from the persisted run (the internal
/// `RunEvent` stream + the post-answer plan stage are not exposed live by
/// `TeamService` today). Live incremental streaming is a later enhancement; the
/// emitted shape, ordering, and content are the contract here.
public enum NDJSONStreamProjector {
    public struct Event: Encodable, Sendable {
        public let schemaVersion: Int
        public let seq: Int
        public let ts: String
        public let event: String
        public let teamRunId: String
        public let data: EventData
        /// RLR-L7: additive marker set true on replayed history lines. Omitted on
        /// encode when nil (live tail lines carry no `replayed` key) so existing
        /// consumers keep decoding — additive field only.
        public let replayed: Bool?
        init(seq: Int, ts: String, event: String, teamRunId: String, data: EventData, replayed: Bool? = nil) {
            self.schemaVersion = 1; self.seq = seq; self.ts = ts
            self.event = event; self.teamRunId = teamRunId; self.data = data
            self.replayed = replayed
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, seq, ts, event, teamRunId, data, replayed
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(schemaVersion, forKey: .schemaVersion)
            try c.encode(seq, forKey: .seq)
            try c.encode(ts, forKey: .ts)
            try c.encode(event, forKey: .event)
            try c.encode(teamRunId, forKey: .teamRunId)
            try c.encode(data, forKey: .data)
            try c.encodeIfPresent(replayed, forKey: .replayed)
        }
    }

    /// The terminal NDJSON event names (RLR-L7 exactly-one-terminal). An
    /// attachment forwards the first of these and drops every later line.
    public static let terminalEventNames: Set<String> = ["teamRunCompleted", "teamRunFailed", "error"]

    /// RLR-L7 gap detection: within one attachment's shared seq space the visible
    /// seqs need not be contiguous (dropped/other-run events consume durable seq),
    /// but they must strictly increase. Returns the first `(previous, next)` pair
    /// that is non-increasing or skips — i.e. a consumer-visible gap/duplicate — or
    /// nil when the run of seqs is strictly ascending with no jumps.
    public static func firstSeqGap(_ seqs: [Int]) -> (expected: Int, actual: Int)? {
        guard seqs.count > 1 else { return nil }
        for i in 1..<seqs.count where seqs[i] != seqs[i - 1] + 1 {
            return (expected: seqs[i - 1] + 1, actual: seqs[i])
        }
        return nil
    }

    /// Flexible per-event data. Nil fields are omitted on encode, so each event
    /// carries only its contract-required keys.
    public struct EventData: Encodable, Sendable {
        public var status: String?
        public var origin: String?
        public var teamPresetId: String?
        public var agentId: String?
        public var modelId: String?
        public var skillId: String?
        public var durationMs: Int?
        public var stageId: String?
        public var planStageId: String?
        public var error: ErrorEnvelope?
        /// RLR-S03c: bounded activity metadata on `workerActivity`/`stageActivity`
        /// lines — the `RunActivityKind` raw value (`message`/`stdout`/…) and an
        /// optional size of the underlying delta/output, **never the text itself**
        /// (non-goal: no raw stdout/stderr/token payload in the NDJSON stream).
        public var activityKind: String?
        public var byteCount: Int?
        public var charCount: Int?
        /// ORS-S02b1: full run projection on snapshot / terminal frames (not a
        /// parallel envelope — still `NDJSONStreamProjector.Event.data`).
        public var teamRun: TeamRunJSON?
        /// ORS-S02b1: terminal `pmTurn` mirror (also nested on `teamRun.pmTurn`).
        public var pmTurn: PMTurnJSON?
        /// ORS-S02b2: attention-required exit reason
        /// (`sourcedBlocker` | `vendorWait` | `observerBudget`).
        public var reason: String?
        /// ORS-S02b2: human-readable attention note. Never labels silence as
        /// stuck/stalled/no-progress — expected silence is named expected.
        public var message: String?
        /// ORS-S02b2: pass-through of `observation.activityMode` on attention frames.
        public var activityMode: String?
        /// ORS-S02b2: true when silence is expected (`terminalOnly` + observer budget).
        public var silenceExpected: Bool?
        /// ORS-S02b2: one recovery nextAction on attention exit (never `showRun`).
        /// Omitted when no honest non-circular recovery exists (observer-budget case).
        public var nextAction: TeamRunJSON.NextAction?

        public init(
            status: String? = nil,
            origin: String? = nil,
            teamPresetId: String? = nil,
            agentId: String? = nil,
            modelId: String? = nil,
            skillId: String? = nil,
            durationMs: Int? = nil,
            stageId: String? = nil,
            planStageId: String? = nil,
            error: ErrorEnvelope? = nil,
            activityKind: String? = nil,
            byteCount: Int? = nil,
            charCount: Int? = nil,
            teamRun: TeamRunJSON? = nil,
            pmTurn: PMTurnJSON? = nil,
            reason: String? = nil,
            message: String? = nil,
            activityMode: String? = nil,
            silenceExpected: Bool? = nil,
            nextAction: TeamRunJSON.NextAction? = nil
        ) {
            self.status = status
            self.origin = origin
            self.teamPresetId = teamPresetId
            self.agentId = agentId
            self.modelId = modelId
            self.skillId = skillId
            self.durationMs = durationMs
            self.stageId = stageId
            self.planStageId = planStageId
            self.error = error
            self.activityKind = activityKind
            self.byteCount = byteCount
            self.charCount = charCount
            self.teamRun = teamRun
            self.pmTurn = pmTurn
            self.reason = reason
            self.message = message
            self.activityMode = activityMode
            self.silenceExpected = silenceExpected
            self.nextAction = nextAction
        }

        private enum CodingKeys: String, CodingKey {
            case status, origin, teamPresetId, agentId, modelId, skillId
            case durationMs, stageId, planStageId, error
            case activityKind, byteCount, charCount, teamRun, pmTurn
            case reason, message, activityMode, silenceExpected, nextAction
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(status, forKey: .status)
            try c.encodeIfPresent(origin, forKey: .origin)
            try c.encodeIfPresent(teamPresetId, forKey: .teamPresetId)
            try c.encodeIfPresent(agentId, forKey: .agentId)
            try c.encodeIfPresent(modelId, forKey: .modelId)
            try c.encodeIfPresent(skillId, forKey: .skillId)
            try c.encodeIfPresent(durationMs, forKey: .durationMs)
            try c.encodeIfPresent(stageId, forKey: .stageId)
            try c.encodeIfPresent(planStageId, forKey: .planStageId)
            try c.encodeIfPresent(error, forKey: .error)
            try c.encodeIfPresent(activityKind, forKey: .activityKind)
            try c.encodeIfPresent(byteCount, forKey: .byteCount)
            try c.encodeIfPresent(charCount, forKey: .charCount)
            try c.encodeIfPresent(teamRun, forKey: .teamRun)
            try c.encodeIfPresent(pmTurn, forKey: .pmTurn)
            try c.encodeIfPresent(reason, forKey: .reason)
            try c.encodeIfPresent(message, forKey: .message)
            try c.encodeIfPresent(activityMode, forKey: .activityMode)
            try c.encodeIfPresent(silenceExpected, forKey: .silenceExpected)
            try c.encodeIfPresent(nextAction, forKey: .nextAction)
        }
    }

    /// ORS-S02b1: max durable journal events replayed on `show --stream`.
    /// Explicit count bound (binding rule 4) — recent window, not the full retention cap.
    public static let streamReplayMaxEvents: Int = 128

    /// ORS-S02b2: finite observer budget (seconds) on a `terminalOnly` driver when
    /// the run carries no wall-clock fact. Replaces the deleted waiter timeout
    /// (`DetachedDispatch.defaultPMTurnWaitTimeoutSeconds` = 7200). Not applied to
    /// healthy `incremental` drivers (normal long work must not become a fake timeout).
    public static let streamObserverBudgetSecondsDefault: TimeInterval = 7_200

    /// ORS-S02b2: derive the terminalOnly observer budget from the run's wall
    /// clock fact when present; otherwise the documented default above.
    public static func streamObserverBudgetSeconds(for run: TeamRun) -> TimeInterval {
        if let wall = run.clockBudgets?.wallTimeoutSeconds, wall > 0 {
            return wall
        }
        return streamObserverBudgetSecondsDefault
    }

    /// Attention-required stream exit reasons (ORS-S02b2). Ends the observer;
    /// is **not** a run-terminal frame (run ownership unchanged).
    public enum AttentionReason: String, Sendable {
        case sourcedBlocker
        case vendorWait
        case observerBudget
    }

    /// Event name for the attention-required observer boundary frame.
    public static let attentionRequiredEventName = "attentionRequired"

    /// Immediate snapshot frame (`teamRunSnapshot`) carrying current `TeamRunJSON`.
    /// Seq 0 is reserved for the pre-history snapshot; durable journal seqs start at 1.
    public static func snapshotLine(teamRunId: String, teamRun: TeamRunJSON, at ts: Date = Date()) -> String {
        let event = Event(
            seq: 0,
            ts: iso(ts),
            event: "teamRunSnapshot",
            teamRunId: teamRunId,
            data: EventData(status: teamRun.teamRun.status.rawValue, teamRun: teamRun)
        )
        return encodeLine(event)
    }

    /// Exactly one terminal frame for an already-terminal run, carrying full
    /// `TeamRunJSON` + `pmTurn`. Not marked `replayed`.
    public static func terminalDeliveryLine(
        teamRunId: String,
        teamRun: TeamRunJSON,
        seq: Int,
        at ts: Date = Date()
    ) -> String {
        let status = teamRun.teamRun.status
        let name: String
        let data: EventData
        switch status {
        case .done:
            name = "teamRunCompleted"
            data = EventData(
                status: status.rawValue,
                planStageId: teamRun.plan?.stageId,
                teamRun: teamRun,
                pmTurn: teamRun.pmTurn
            )
        default:
            name = "teamRunFailed"
            data = EventData(
                status: status.rawValue,
                error: teamRun.errors.first ?? ErrorEnvelope(
                    code: "TEAM_RUN_FAILED",
                    message: "team run \(status.rawValue)",
                    requiresManual: false,
                    retryable: true,
                    runId: teamRunId
                ),
                teamRun: teamRun,
                pmTurn: teamRun.pmTurn
            )
        }
        return encodeLine(Event(
            seq: seq, ts: iso(ts), event: name, teamRunId: teamRunId, data: data
        ))
    }

    /// Typed error frame on the stream path (ORS binding rule 7). Terminal
    /// (`error`); attachment consumers treat it as the one terminal.
    public static func streamErrorLine(
        teamRunId: String,
        code: String,
        message: String,
        seq: Int,
        at ts: Date = Date()
    ) -> String {
        let event = Event(
            seq: seq,
            ts: iso(ts),
            event: "error",
            teamRunId: teamRunId,
            data: EventData(error: ErrorEnvelope(
                code: code,
                message: message,
                requiresManual: true,
                retryable: false,
                runId: teamRunId.isEmpty ? nil : teamRunId
            ))
        )
        return encodeLine(event)
    }

    /// ORS-S02b2: attention-required observer exit frame. Ends the stream without
    /// claiming run terminal. Recovery `nextAction` is never `showRun`.
    public static func attentionRequiredLine(
        teamRunId: String,
        teamRun: TeamRunJSON,
        reason: AttentionReason,
        message: String,
        seq: Int,
        silenceExpected: Bool = false,
        nextAction: TeamRunJSON.NextAction? = nil,
        at ts: Date = Date()
    ) -> String {
        let event = Event(
            seq: seq,
            ts: iso(ts),
            event: attentionRequiredEventName,
            teamRunId: teamRunId,
            data: EventData(
                status: teamRun.teamRun.status.rawValue,
                teamRun: teamRun,
                reason: reason.rawValue,
                message: message,
                activityMode: teamRun.observation.activityMode.rawValue,
                silenceExpected: silenceExpected ? true : nil,
                nextAction: nextAction
            )
        )
        return encodeLine(event)
    }

    public static func events(for run: TeamRun) -> [Event] {
        var out: [Event] = []
        var seq = 0
        func add(_ event: String, _ ts: Date, _ data: EventData) {
            seq += 1
            out.append(Event(seq: seq, ts: iso(ts), event: event, teamRunId: run.id, data: data))
        }

        let created = run.createdAt
        let lastFinish = run.answers.compactMap(\.result.timing.finishedAt).max() ?? created

        add("teamRunStarted", created, EventData(
            status: TeamRunJSON.Status.running.rawValue,
            origin: TeamRunJSONMapper.mapOrigin(run.origin).rawValue,
            teamPresetId: run.presetId
        ))

        for agent in run.workers {
            let answer = run.workerAnswer(workerId: agent.id)
            let startedAt = answer?.result.timing.startedAt ?? created
            add("workerStarted", startedAt, EventData(agentId: agent.id, modelId: agent.modelId, skillId: agent.skillId))
            guard let answer else { continue }
            let endAt = answer.result.timing.finishedAt ?? startedAt
            switch answer.result.status {
            case .done:
                add("workerAnswered", endAt, EventData(agentId: agent.id, durationMs: answer.result.timing.durationMs))
            case .failed, .timedOut:
                add("workerFailed", endAt, EventData(agentId: agent.id, error: workerError(answer, runId: run.id)))
            default:
                break   // queued/running/skipped/cancelled: no terminal worker event
            }
        }

        if let plan = run.latestStage(.plan) {
            add("planStarted", lastFinish, EventData(agentId: plan.producedByAgentId, stageId: plan.id))
            if plan.status == .done {
                add("planWritten", lastFinish, EventData(agentId: plan.producedByAgentId, stageId: plan.id))
            }
        }

        switch TeamRunJSONMapper.mapRun(run.status) {
        case .done:
            add("teamRunCompleted", lastFinish, EventData(
                status: TeamRunJSON.Status.done.rawValue,
                planStageId: run.latestStage(.plan).flatMap { $0.status == .done ? $0.id : nil }
            ))
        default:
            add("teamRunFailed", lastFinish, EventData(
                status: TeamRunJSONMapper.mapRun(run.status).rawValue,
                error: ErrorEnvelope(code: "TEAM_RUN_FAILED", message: "team run \(run.status.rawValue)", requiresManual: false, retryable: true, runId: run.id)
            ))
        }
        return out
    }

    /// One compact (single-line, sorted-key) JSON object per event — NDJSON.
    public static func lines(for run: TeamRun) -> [String] {
        events(for: run).map(encodeLine)
    }

    /// Maps the live internal `RunEvent` stream (from `TeamService.run(events:)`)
    /// into public NDJSON events as they arrive — the live counterpart to
    /// `lines(for:)`. Carries through the event's **durable per-Mac `seq`**
    /// (`RemoteRunEventJournal`, stamped at append) rather than minting its own,
    /// so the stream seq survives coordinator restart + reattach (RLR-L7).
    /// Intermediate internal transitions (e.g. `answers_in`) map to nil and are dropped.
    /// RLR-S03c: worker deltas/output and stage output — previously dropped in full
    /// — now project as bounded `workerActivity`/`stageActivity` metadata (never
    /// the raw text), so the stream stays live between `started` and the terminal.
    public struct LiveMapper {
        public init() {}

        /// Project one internal event to its public NDJSON `Event`, carrying the
        /// durable `seq`. `replayed` marks history lines on a replay attach.
        public func event(for runEvent: RunEvent, replayed: Bool = false) -> Event? {
            guard let mapped = Self.map(runEvent) else { return nil }
            return Event(seq: Int(runEvent.seq), ts: NDJSONStreamProjector.iso(runEvent.ts),
                         event: mapped.name, teamRunId: mapped.runId, data: mapped.data,
                         replayed: replayed ? true : nil)
        }

        public func line(for runEvent: RunEvent) -> String? {
            guard let event = event(for: runEvent) else { return nil }
            return NDJSONStreamProjector.encodeLine(event)
        }

        private static func map(_ e: RunEvent) -> (name: String, runId: String, data: EventData)? {
            func str(_ k: String) -> String? { if case .string(let v)? = e.payload[k] { return v }; return nil }
            func intVal(_ k: String) -> Int? { if case .int(let v)? = e.payload[k] { return v }; return nil }
            let runId = str("runId") ?? ""

            switch e.kind {
            case RunEventKind.runStatusChanged:
                switch str("to") ?? "" {
                case RunStatus.fanningOut.rawValue, RunStatus.running.rawValue:
                    // One-worker runs start at `running` (RLR-L3); multi-worker at `fanning_out`.
                    return ("teamRunStarted", runId, EventData(status: TeamRunJSON.Status.running.rawValue, origin: str("origin"), teamPresetId: str("presetId")))
                case RunStatus.complete.rawValue, RunStatus.partial.rawValue, RunStatus.done.rawValue:
                    return ("teamRunCompleted", runId, EventData(status: TeamRunJSON.Status.done.rawValue, planStageId: str("planStageId")))
                case RunStatus.failed.rawValue, RunStatus.cancelled.rawValue, RunStatus.timedOut.rawValue:
                    let to = str("to") ?? RunStatus.failed.rawValue
                    return ("teamRunFailed", runId, EventData(
                        status: TeamRunJSONMapper.mapRun(RunStatus(rawValue: to) ?? .failed).rawValue,
                        error: ErrorEnvelope(code: "TEAM_RUN_FAILED", message: str("reason") ?? "team run \(to)", requiresManual: false, retryable: true, runId: runId.isEmpty ? nil : runId)))
                default:
                    return nil   // intermediate transition (answers_in / planning / …)
                }
            case RunEventKind.workerStatusChanged:
                let to = str("to") ?? ""
                let workerId = str("workerId")
                switch to {
                case WorkerAnswerStatus.running.rawValue:
                    return ("workerStarted", runId, EventData(agentId: workerId, modelId: str("modelId"), skillId: str("skillId")))
                case WorkerAnswerStatus.done.rawValue:
                    return ("workerAnswered", runId, EventData(agentId: workerId, durationMs: intVal("durationMs")))
                case WorkerAnswerStatus.failed.rawValue, WorkerAnswerStatus.timedOut.rawValue:
                    return ("workerFailed", runId, EventData(agentId: workerId, error: ErrorEnvelope(
                        code: to == WorkerAnswerStatus.timedOut.rawValue ? "TEAM_RUN_TIMEOUT" : "AGENT_FAILED",
                        message: str("reason") ?? "worker did not produce an answer",
                        requiresManual: false, retryable: true, runId: runId.isEmpty ? nil : runId, agentId: workerId)))
                default:
                    return nil   // queued / skipped / cancelled — no terminal worker event
                }
            case RunEventKind.stageStarted where str("purpose") == "plan":
                return ("planStarted", runId, EventData(agentId: str("workerId"), stageId: str("stageId")))
            case RunEventKind.stageCompleted where str("purpose") == "plan":
                return ("planWritten", runId, EventData(agentId: str("workerId"), stageId: str("stageId")))
            // RLR-S03c: the live tokens/output that used to fall through to `default`
            // (dropped) now project as bounded `workerActivity`/`stageActivity`
            // metadata. Shares the ONE classifier (`RunActivity.activityKind(for:)`)
            // with the S03a journal projection so the stream and `run.json` never
            // disagree about what counts as activity. `nil` from the classifier
            // (should not occur for these kinds) still drops the line — belt and
            // suspenders, never crash on an unexpected payload shape.
            case RunEventKind.workerAnswerDelta, RunEventKind.workerReasoningDelta, RunEventKind.workerOutput:
                guard let activity = RunActivity.activityKind(for: e) else { return nil }
                let text = str("text")
                return ("workerActivity", runId, EventData(
                    agentId: str("workerId"),
                    activityKind: activity.rawValue,
                    byteCount: text.map { $0.utf8.count },
                    charCount: text.map(\.count)
                ))
            case RunEventKind.stageOutput:
                guard let activity = RunActivity.activityKind(for: e) else { return nil }
                let text = str("text")
                return ("stageActivity", runId, EventData(
                    agentId: str("workerId"), stageId: str("stageId"),
                    activityKind: activity.rawValue,
                    byteCount: text.map { $0.utf8.count },
                    charCount: text.map(\.count)
                ))
            default:
                return nil
            }
        }
    }

    /// One live/replay attachment to a run's `--stream` NDJSON (RLR-L7). Owns two
    /// invariants the raw `LiveMapper` cannot:
    ///
    /// - **Exactly one terminal per attachment.** The first terminal event is
    ///   forwarded; every line after it — a late worker event, a duplicate
    ///   terminal — is dropped. If the attachment closes before a terminal
    ///   arrived (early close / ack-and-close), `closingLine` synthesizes exactly
    ///   one so every attachment ends terminal.
    /// - **Durable shared seq space.** Live and replayed lines both carry the
    ///   event's durable per-Mac `seq`; history is marked `replayed:true`. Because
    ///   the seq is allocated by `RemoteRunEventJournal` before projection, a
    ///   reattach or coordinator restart continues from `lastSeq` with no reset,
    ///   and gaps stay detectable by seq (`firstSeqGap`).
    public final class NDJSONAttachment {
        private let mapper = LiveMapper()
        private var didEmitTerminal = false
        private var lastSeq = 0
        private var runId: String?

        public init() {}

        /// True once this attachment has forwarded (or synthesized) its terminal.
        public var terminalEmitted: Bool { didEmitTerminal }

        /// Forward one live event as an NDJSON line. Returns nil when the event
        /// maps to no public line OR a terminal already went out (post-terminal
        /// drop). The first terminal flips `terminalEmitted`.
        public func liveLine(for runEvent: RunEvent) -> String? {
            emit(runEvent, replayed: false)
        }

        /// Replay durable history (from `RemoteRunEventJournal.replay(after:)`)
        /// as NDJSON lines marked `replayed:true`, sharing the run's one seq
        /// space with the subsequent live tail. Stops emitting once a terminal is
        /// seen in history (exactly-one-terminal holds across replay + tail too).
        public func replayLines(_ events: [RunEvent]) -> [String] {
            events.compactMap { emit($0, replayed: true) }
        }

        private func emit(_ runEvent: RunEvent, replayed: Bool) -> String? {
            guard !didEmitTerminal else { return nil }
            guard let event = mapper.event(for: runEvent, replayed: replayed) else { return nil }
            if runId == nil { runId = event.teamRunId }
            lastSeq = max(lastSeq, event.seq)
            if NDJSONStreamProjector.terminalEventNames.contains(event.event) { didEmitTerminal = true }
            return NDJSONStreamProjector.encodeLine(event)
        }

        /// Close the attachment. When no terminal was forwarded — an early close,
        /// or an ack-and-close snapshot whose ack IS its terminal (RLR-L7) —
        /// synthesize exactly one terminal so the attachment always ends terminal.
        /// Returns nil when a real terminal already went out (no double-terminal).
        public func closingLine(status: TeamRunJSON.Status = .failed, at ts: Date = Date()) -> String? {
            guard !didEmitTerminal else { return nil }
            didEmitTerminal = true
            lastSeq += 1
            let name = status == .done ? "teamRunCompleted" : "teamRunFailed"
            let data: EventData = status == .done
                ? EventData(status: status.rawValue)
                : EventData(status: status.rawValue, error: ErrorEnvelope(
                    code: "STREAM_CLOSED", message: "stream closed before a terminal event",
                    requiresManual: false, retryable: true, runId: runId))
            let event = Event(seq: lastSeq, ts: NDJSONStreamProjector.iso(ts),
                              event: name, teamRunId: runId ?? "", data: data)
            return NDJSONStreamProjector.encodeLine(event)
        }
    }

    static func encodeLine(_ event: Event) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(event)) ?? Data("{}".utf8), as: UTF8.self)
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private static func workerError(_ a: TeamAnswer, runId: String) -> ErrorEnvelope {
        ErrorEnvelope(
            code: a.result.status == .timedOut ? "TEAM_RUN_TIMEOUT" : "AGENT_FAILED",
            message: a.result.errorReason ?? "worker did not produce an answer",
            requiresManual: false, retryable: true, runId: runId, agentId: a.memberId
        )
    }
}
