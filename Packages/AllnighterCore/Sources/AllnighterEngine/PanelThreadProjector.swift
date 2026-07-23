import Foundation
import AllnighterCore

/// Projects a Panel (`PanelState`) onto ONE `WorkThread` per panel so the Mac inbox
/// shows the jury live "for free" (`docs/phases/Pilot_Panel.md` decision 12 / PN-S05)
/// without a second GUI surface. Composition, not hardcoding: `PanelCoordinator` holds
/// this as an optional collaborator (nil in tests/headless callers) and calls it at its
/// own choke points — this type never drives the jury, only observes it.
///
/// Identity: the projected thread's `id` IS the panel's own `state.id` (already a
/// collision-free `panel_<uuid>` string). That's the provenance slot — no new field on
/// `WorkThread` or `PanelState`. `store.get(state.id)` is the lookup.
///
/// Turn identity is deterministic so `sync(state:now:)` is idempotent and safe after
/// EVERY `PanelState` mutation (`PanelCoordinator.persist` calls it unconditionally):
/// - brief: `"<panelId>_r<round>_brief"`
/// - seat:  `"<panelId>_r<round>_seat_<workerId>"`
///
/// **Rerun turns: REPLACE (not append).** A `--seats a,b` rerun is a new attempt on the
/// same round that REPLACE those seats in `round.seatResults` (PN-S03). The thread turn
/// for a seat is keyed by round + workerId only, so `sync` rewrites that seat's turn
/// text/status/runId to the latest merged result. Attempt history remains run-truth on
/// `PanelRound.attempts` — the thread shows the current jury answer, not a second ledger.
///
/// Unlike Relay, seat report text lives on `SeatResult.report` itself (Panel does not
/// re-fetch from `RunStore`); `runId` is attached when present as a reference only.
public struct PanelThreadProjector: Sendable {
    private let store: ThreadStore

    public init(store: ThreadStore = ThreadStore()) {
        self.store = store
    }

    // MARK: - Entry points (called by PanelCoordinator)

    /// Creates the panel's thread if missing, and (re-)binds it to `projectId`.
    /// Called at `start` — the only place `Config.projectId` is in scope for a brand-new
    /// panel. Best-effort: a `ThreadStore` failure never aborts the panel; panel durability
    /// is `PanelState`.
    public func started(state: PanelState, projectId: String?) {
        if store.get(state.id) == nil {
            guard let created = try? store.create(
                id: state.id,
                title: Self.title(forTargetPath: state.targetPath),
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

    /// Syncs every round's brief + seat turns onto the thread. Called after EVERY
    /// `PanelState` persist — the single choke point every mutation already runs through.
    /// No-op if `started` was never called (or failed) — never crashes the panel loop.
    public func sync(state: PanelState, now: Date) {
        guard var thread = store.get(state.id) else { return }
        for round in state.rounds {
            syncBrief(round: round, state: state, thread: &thread, now: now)
            syncSeats(round: round, state: state, thread: &thread, now: now)
        }
    }

    // MARK: - Per-round projection

    /// The brief is user-authored and known at dispatch — written `.done` immediately
    /// (never a running placeholder). Reruns that change the brief rewrite the same turn.
    private func syncBrief(
        round: PanelRound,
        state: PanelState,
        thread: inout WorkThread,
        now: Date
    ) {
        let turnId = "\(state.id)_r\(round.roundNumber)_brief"
        if var existing = thread.turn(id: turnId) {
            // Self-heal: brief text can change on a focus rerun of the same round.
            if existing.text != round.brief || existing.status != .done {
                existing.status = .done
                existing.text = round.brief
                existing.author = .user
                existing.completedAt = existing.completedAt ?? round.startedAt
                if let updated = try? store.updateTurn(existing, inThreadId: thread.id, now: now) {
                    thread = updated
                }
            }
            return
        }
        let turn = ThreadTurn(
            id: turnId,
            threadId: thread.id,
            kind: .userMessage,
            status: .done,
            createdAt: round.startedAt,
            completedAt: round.startedAt,
            author: .user,
            text: round.brief
        )
        if let updated = try? store.appendTurn(turn, toThreadId: thread.id, now: now) {
            thread = updated
        }
    }

    /// Each seat's report is a worker turn. In-flight rounds (`finishedAt == nil`) show
    /// `.running` placeholders for seats that still have empty placeholders on the round;
    /// settled rounds rewrite every seat turn from the merged `seatResults` (REPLACE on
    /// rerun — same turn id, latest text/status/runId). Seats that still hold prior
    /// results during a partial-seat rerun stay settled until their own result updates.
    private func syncSeats(
        round: PanelRound,
        state: PanelState,
        thread: inout WorkThread,
        now: Date
    ) {
        for seat in round.seatResults {
            let turnId = "\(state.id)_r\(round.roundNumber)_seat_\(seat.workerId)"
            let showRunning =
                state.status == .running
                && round.finishedAt == nil
                && seatLooksInFlight(seat)
            if showRunning {
                syncRunningSeat(
                    turnId: turnId, seat: seat, thread: &thread, now: now, createdAt: round.startedAt
                )
            } else if !seatLooksInFlight(seat) || round.finishedAt != nil {
                syncSettledSeat(
                    turnId: turnId,
                    seat: seat,
                    thread: &thread,
                    now: now,
                    createdAt: round.startedAt,
                    completedAt: round.finishedAt ?? now
                )
            }
        }
    }

    /// Current running seats plus legacy empty placeholders opened at dispatch time.
    private func seatLooksInFlight(_ seat: SeatResult) -> Bool {
        seat.status == .running
            || (seat.status == .empty
                && seat.report.isEmpty
                && seat.runId == nil
                && seat.reason == nil)
    }

    private func syncRunningSeat(
        turnId: String,
        seat: SeatResult,
        thread: inout WorkThread,
        now: Date,
        createdAt: Date
    ) {
        if var existing = thread.turn(id: turnId) {
            if existing.status != .running {
                existing.status = .running
                existing.completedAt = nil
                existing.text = nil
                existing.runId = nil
                existing.workerId = seat.workerId
                existing.author = .worker
                if let updated = try? store.updateTurn(existing, inThreadId: thread.id, now: now) {
                    thread = updated
                }
            }
            return
        }
        let turn = ThreadTurn(
            id: turnId,
            threadId: thread.id,
            kind: .workerChat,
            status: .running,
            createdAt: createdAt,
            author: .worker,
            workerId: seat.workerId
        )
        if let updated = try? store.appendTurn(turn, toThreadId: thread.id, now: now) {
            thread = updated
        }
    }

    private func syncSettledSeat(
        turnId: String,
        seat: SeatResult,
        thread: inout WorkThread,
        now: Date,
        createdAt: Date,
        completedAt: Date
    ) {
        let status = Self.turnStatus(for: seat)
        let text = Self.seatText(for: seat)
        if var existing = thread.turn(id: turnId) {
            let needsUpdate =
                existing.status != status
                || existing.text != text
                || existing.runId != seat.runId
                || existing.workerId != seat.workerId
            guard needsUpdate else { return }
            existing.status = status
            existing.text = text
            existing.runId = seat.runId
            existing.workerId = seat.workerId
            existing.author = .worker
            existing.completedAt = completedAt
            if let updated = try? store.updateTurn(existing, inThreadId: thread.id, now: now) {
                thread = updated
            }
            return
        }
        let turn = ThreadTurn(
            id: turnId,
            threadId: thread.id,
            kind: .workerChat,
            status: status,
            createdAt: createdAt,
            completedAt: completedAt,
            author: .worker,
            text: text,
            workerId: seat.workerId,
            runId: seat.runId
        )
        if let updated = try? store.appendTurn(turn, toThreadId: thread.id, now: now) {
            thread = updated
        }
    }

    // MARK: - Mapping

    /// Map seat ledger status onto turn status. Failed/timed-out seats remain honest
    /// (`.failed`/`.timedOut`); parked-calm for a fully successful round follows because
    /// those seats land as `.done` and no system event blocks attention.
    static func turnStatus(for seat: SeatResult) -> ThreadTurnStatus {
        switch seat.status {
        case .done, .empty:
            return .done
        case .running:
            return .running
        case .failed:
            return .failed
        case .timedOut:
            return .timedOut
        }
    }

    /// Verbatim report when present; otherwise the failure reason so empty failures
    /// still leave a readable receipt.
    static func seatText(for seat: SeatResult) -> String {
        if !seat.report.isEmpty { return seat.report }
        return seat.reason ?? ""
    }

    // MARK: - Title

    /// "Title from the target name" — last path component, extension stripped,
    /// `_`/`-` → spaces. Falls back to a fixed label so `ThreadStore.create` never
    /// sees an empty title.
    static func title(forTargetPath targetPath: String) -> String {
        let base = (targetPath as NSString).lastPathComponent
        let stem = (base as NSString).deletingPathExtension
        let cleaned = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Panel" : "Panel: \(cleaned)"
    }
}
