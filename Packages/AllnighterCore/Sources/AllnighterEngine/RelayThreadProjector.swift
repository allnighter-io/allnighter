import Foundation
import AllnighterCore

/// Projects a PM Relay (`RelayState`) onto ONE `WorkThread` per relay, so the Mac inbox
/// shows the loop live "for free" (`docs/phases/PM_Relay.md` §6 R-S07) without a second
/// GUI surface. Composition, not hardcoding: `RelayCoordinator` holds this as an optional
/// collaborator (nil in tests/headless callers) and calls it at its own choke points —
/// this type never drives the loop, only observes it.
///
/// Identity: the projected thread's `id` IS the relay's own `state.id` (already a
/// collision-free `relay_<uuid>` string, `RelayCoordinator.idFactory`). That's the
/// "metadata slot" that carries the relay's provenance — no new field on `WorkThread` or
/// `RelayState`, so this stays a projection-only slice with zero new durable primitives
/// beyond the thread turns themselves. `store.get(state.id)` is the lookup, mirroring how
/// `ThreadStore.threadId(forRunId:)` derives run→thread association from turn truth rather
/// than a second index.
///
/// Turn identity inside the thread is deterministic (`"<relayId>_pm<round>"`,
/// `"<relayId>_dev<round>"`, `"<relayId>_escalate<round>"`, `"<relayId>_stopped"`) so
/// `sync(state:now:)` is idempotent and safe to call after EVERY `RelayState` mutation
/// (it is — `RelayCoordinator.persist` calls it unconditionally): each call only appends
/// turns that don't exist yet and only updates a turn when the round's underlying
/// `RunStore` record actually changed (e.g. a verdict-parse re-ask supersedes the first PM
/// attempt's `pmRunId` — `sync` re-fetches and re-settles the SAME thread turn rather than
/// leaving the discarded first attempt's text behind).
///
/// PM/dev text is never carried on `RelayState`/`RelayRound` (run-truth lives in
/// `RunStore`, referenced by `pmRunId`/`devRunId` — see `RelayRound`'s own doc comment:
/// "never a second copy of run-truth"). This type reads it back from the SAME `RunStore`
/// root the coordinator dispatched through, exactly like `RelayCoordinator.devReportText`
/// does for the next round's PM prompt.
public struct RelayThreadProjector: Sendable {
    private let store: ThreadStore
    private let runStore: RunStore

    public init(store: ThreadStore = ThreadStore(), runStore: RunStore = RunStore()) {
        self.store = store
        self.runStore = runStore
    }

    // MARK: - Entry points (called by RelayCoordinator)

    /// Creates the relay's thread if it doesn't exist yet, and (re-)binds it to
    /// `projectId`. Called at `run(config:)`/`resume(...)` — the only two places
    /// `RelayCoordinator.Config.projectId` is in scope; `RelayState` itself doesn't carry
    /// it (PM_Relay.md: per-invocation, not persisted). Best-effort: a `ThreadStore`
    /// failure here never aborts the relay — the relay's own durability is `RelayState`.
    public func started(state: RelayState, projectId: String?) {
        if store.get(state.id) == nil {
            guard let created = try? store.create(
                id: state.id,
                title: Self.title(forDocPath: state.docPath),
                now: state.createdAt,
                workingDir: state.projectRoot
            ) else { return }
            if let projectId {
                _ = try? store.bindProject(threadId: created.id, projectId: projectId)
            }
        } else if let projectId {
            _ = try? store.bindProject(threadId: state.id, projectId: projectId)
        }
    }

    /// Syncs every round + the terminal `stopped` note onto the thread. Called after
    /// EVERY `RelayState` persist (`RelayCoordinator.persist`) — the single choke point
    /// every mutation already runs through — so this always observes a state snapshot
    /// taken immediately after the mutation that produced it (critical for `state.note`,
    /// which is a single mutable field reused across multiple escalations across resumes:
    /// syncing synchronously, right after each `persist`, is what guarantees round N's
    /// escalation turn captures round N's note before a later round can overwrite it).
    /// No-op if `started` was never called (or failed) — never crashes the relay loop.
    public func sync(state: RelayState, now: Date) {
        guard var thread = store.get(state.id) else { return }
        for round in state.rounds {
            syncPMTurn(round: round, state: state, thread: &thread, now: now)
            syncDevTurn(round: round, state: state, thread: &thread, now: now)
            syncEscalation(round: round, state: state, thread: &thread, now: now)
        }
        syncStopped(state: state, thread: &thread, now: now)
    }

    // MARK: - Per-round projection

    /// The PM turn: appended `running` the moment the round starts (before the PM CLI
    /// even returns — the one live signal this slice adds, since a PM turn can run for
    /// minutes), then settled to `done` with the verbatim `RunStore` text once
    /// `round.pmRunId` lands. `existing.runId != pmRunId` (not `existing.status ==
    /// .running`) is the re-sync trigger so a verdict-parse re-ask — which supersedes
    /// `round.pmRunId` with the second attempt's id — corrects an already-settled turn's
    /// text instead of leaving the discarded first attempt behind (§4.1).
    private func syncPMTurn(round: RelayRound, state: RelayState, thread: inout WorkThread, now: Date) {
        let turnId = "\(state.id)_pm\(round.roundNumber)"
        if let submission = round.externalSubmission {
            syncExternalPMTurn(turnId: turnId, submission: submission, round: round, thread: &thread, now: now)
            return
        }
        guard let existing = thread.turn(id: turnId) else {
            let turn = ThreadTurn(
                id: turnId, threadId: thread.id, kind: .workerChat, status: .running,
                createdAt: round.startedAt, author: .worker, workerId: state.pmWorkerId
            )
            if let updated = try? store.appendTurn(turn, toThreadId: thread.id, now: now) { thread = updated }
            return
        }
        if let pmRunId = round.pmRunId, existing.runId != pmRunId,
           let text = runStore.load(runId: pmRunId)?.workerAnswers.first?.output {
            var settled = existing
            settled.status = .done
            settled.text = text
            settled.workerId = state.pmWorkerId
            settled.runId = pmRunId
            settled.completedAt = round.finishedAt ?? now
            if let updated = try? store.updateTurn(settled, inThreadId: thread.id, now: now) { thread = updated }
        } else if round.pmRunId == nil, let outcome = round.outcome, outcome != .continued,
                  round.roundNumber == state.rounds.count {
            // The PM turn never delivered this round (dispatch error, budget exhausted,
            // or an `--until` deadline) — settle the placeholder so liveness never sticks.
            // `RelayCoordinator.finishRound` persists TWICE for this outcome (once with
            // `round.outcome` set but before `apply` records the real reason in
            // `state.note`, once after) — gated on `round.roundNumber == state.rounds.count`
            // (this round hasn't been superseded by a later one) rather than "settle once
            // from `.running`", so the SECOND persist can still correct the placeholder
            // fallback text to the real reason once it lands, without a later escalation
            // ever overwriting an already-superseded round's turn.
            let text = state.note ?? "PM turn did not complete this round."
            if existing.status == .running || existing.text != text {
                var settled = existing
                settled.status = (outcome == .stopped) ? .cancelled : .failed
                settled.completedAt = round.finishedAt ?? now
                settled.text = text
                if let updated = try? store.updateTurn(settled, inThreadId: thread.id, now: now) { thread = updated }
            }
        }
    }

    /// Pilot's PM turn (`docs/phases/Pilot_Relay.md` PL-S05, `pmMode == .external`):
    /// there is no PM model dispatch to wait on — `RelayCoordinator.runExternalRound`
    /// only ever persists a round AFTER the piloting session's submission already
    /// parsed (and, for `continue`, cleared `HandoverGate`), so the round is a complete,
    /// immutable record from the moment it first lands. Rendered `.done` immediately
    /// (never an optimistic `.running` placeholder — there's nothing left to wait for),
    /// with the submission verbatim — verdict tail included, same "verbatim, unedited"
    /// contract a spawned PM turn's text carries.
    ///
    /// Attribution is the "distinct from a spawned PM" signal the doc calls for:
    /// `author: .user` (a live human/agent session) instead of `.worker`, and
    /// `workerId: nil` (no model dispatched) instead of `state.pmWorkerId`'s sentinel —
    /// existing `ThreadTurn` fields carry this with no new type.
    ///
    /// A pilot round's `verdict`/`gate`/`externalSubmission` never change after the
    /// round first lands (unlike a spawned round's verdict-parse re-ask, which
    /// supersedes `pmRunId`), so this turn is written once and never revisited.
    private func syncExternalPMTurn(turnId: String, submission: String, round: RelayRound, thread: inout WorkThread, now: Date) {
        guard thread.turn(id: turnId) == nil else { return }
        let turn = ThreadTurn(
            id: turnId, threadId: thread.id, kind: .workerChat, status: .done,
            createdAt: round.startedAt, completedAt: round.finishedAt ?? round.startedAt,
            author: .user, text: submission, workerId: nil
        )
        if let updated = try? store.appendTurn(turn, toThreadId: thread.id, now: now) { thread = updated }
    }

    /// The dev turn: only ever dispatched when the PM verdict was `continue` AND the
    /// handover cleared `HandoverGate` (PM_Relay.md §2 step 5) — that's this method's
    /// guard, so a `done`/`escalate` verdict round or a gate-blocked round never gets a
    /// phantom dev placeholder. Same optimistic-running → settle-by-runId shape as the PM
    /// turn; also self-heals to a terminal status if the dev dispatch itself never
    /// delivered (round outcome escalated/stopped with no `devRunId`).
    private func syncDevTurn(round: RelayRound, state: RelayState, thread: inout WorkThread, now: Date) {
        guard round.verdict?.verdict == .continueRelay, round.gate?.allowed == true else { return }
        let turnId = "\(state.id)_dev\(round.roundNumber)"
        guard let existing = thread.turn(id: turnId) else {
            let turn = ThreadTurn(
                id: turnId, threadId: thread.id, kind: .workerChat, status: .running,
                createdAt: round.finishedAt ?? round.startedAt, author: .worker, workerId: state.devWorkerId
            )
            if let updated = try? store.appendTurn(turn, toThreadId: thread.id, now: now) { thread = updated }
            return
        }
        if let devRunId = round.devRunId, existing.runId != devRunId,
           let text = runStore.load(runId: devRunId)?.workerAnswers.first?.output {
            var settled = existing
            settled.status = .done
            settled.text = text
            settled.workerId = state.devWorkerId
            settled.runId = devRunId
            settled.completedAt = round.finishedAt ?? now
            if let updated = try? store.updateTurn(settled, inThreadId: thread.id, now: now) { thread = updated }
        } else if round.devRunId == nil, let outcome = round.outcome, outcome != .continued,
                  round.roundNumber == state.rounds.count {
            // Same two-persist-calls reasoning as `syncPMTurn`'s failure branch above.
            let text = state.note ?? "Dev turn did not complete this round."
            if existing.status == .running || existing.text != text {
                var settled = existing
                settled.status = (outcome == .stopped) ? .cancelled : .failed
                settled.completedAt = round.finishedAt ?? now
                settled.text = text
                if let updated = try? store.updateTurn(settled, inThreadId: thread.id, now: now) { thread = updated }
            }
        }
    }

    /// Escalation: an open (`.running`) `system_event` turn keyed to `.relayEscalated` —
    /// `ThreadTurn.requiresUserAttention` treats that as blocking (same shape as
    /// `signInRequired`/`manualPaste`), so `WorkThread.needsAttention` flips true the
    /// moment this lands, no new stored liveness field. Cleared to `.done` the next time
    /// `sync` observes `state.status != .escalated` (i.e. right after
    /// `RelayCoordinator.resume` flips it back to `.running`) — mirroring
    /// `AgentChatCoordinator.completeManualPaste`'s "resolve the open note" shape.
    private func syncEscalation(round: RelayRound, state: RelayState, thread: inout WorkThread, now: Date) {
        guard round.outcome == .escalated else { return }
        let turnId = "\(state.id)_escalate\(round.roundNumber)"
        if var existing = thread.turn(id: turnId) {
            if state.status != .escalated {
                guard !existing.status.isTerminal else { return }
                existing.status = .done
                existing.completedAt = now
                if let updated = try? store.updateTurn(existing, inThreadId: thread.id, now: now) { thread = updated }
                return
            }
            // Still the CURRENT escalation (not yet resumed): `RelayCoordinator.finishRound`
            // persists once before `apply` records the real reason in `state.note` and once
            // after — refresh the fallback text to the real one once it lands. Gated on
            // `state.status == .escalated` (not "always"), so a LATER round's escalation
            // note, after a resume, can never bleed backward into this already-cleared turn.
            if let note = state.note, existing.text != note, !existing.status.isTerminal {
                existing.text = note
                if let updated = try? store.updateTurn(existing, inThreadId: thread.id, now: now) { thread = updated }
            }
            return
        }
        let text = state.note ?? "PM escalated (round \(round.roundNumber))."
        let turn = ThreadTurn(
            id: turnId, threadId: thread.id, kind: .systemEvent, status: .running,
            createdAt: round.finishedAt ?? now, author: .system, text: text,
            systemEvent: .relayEscalated
        )
        if let updated = try? store.appendTurn(turn, toThreadId: thread.id, now: now) { thread = updated }
    }

    /// A hard ceiling (`--max-rounds`/`--until`/stagnation) — non-blocking, terminal, and
    /// not tied to any one round (the ceiling check in `RelayCoordinator.loop` can fire
    /// before a round even starts), so this is keyed once per relay rather than per round.
    private func syncStopped(state: RelayState, thread: inout WorkThread, now: Date) {
        guard state.status == .stopped else { return }
        let turnId = "\(state.id)_stopped"
        guard thread.turn(id: turnId) == nil else { return }
        let turn = ThreadTurn(
            id: turnId, threadId: thread.id, kind: .systemEvent, status: .done,
            createdAt: state.finishedAt ?? now, completedAt: state.finishedAt ?? now,
            author: .system, text: state.stoppedReason ?? "Relay stopped.",
            systemEvent: .relayStopped
        )
        if let updated = try? store.appendTurn(turn, toThreadId: thread.id, now: now) { thread = updated }
    }

    // MARK: - Title

    /// "Title from the doc name" (PM_Relay.md §6 R-S07) — the spec doc's last path
    /// component, extension stripped, `_`/`-` turned into spaces. Falls back to a fixed
    /// label so `ThreadStore.create` never sees an empty title.
    static func title(forDocPath docPath: String) -> String {
        let base = (docPath as NSString).lastPathComponent
        let stem = (base as NSString).deletingPathExtension
        let cleaned = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "PM Relay" : "PM Relay: \(cleaned)"
    }
}
