import Foundation
import SwiftUI
import AllnighterCore
import AllnighterEngine

/// Pure view-state for the Work Threads surfaces. No I/O, no SwiftUI state — so
/// triage ordering and turn presentation are unit-testable without a running
/// app. All values derive from `WorkThread` / `ThreadTurn` truth.
enum ThreadsPresenter {

    // MARK: - Thread list triage

    /// The Thread List row order from 01_Work_Threads_MLP.md:
    /// pinned+attention → attention → pinned+running → running →
    /// pinned recent → recent (by updatedAt). Archived threads are excluded.
    static func triaged(_ threads: [WorkThread]) -> [WorkThread] {
        threads
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let l = bucket(lhs), r = bucket(rhs)
                if l != r { return l < r }
                return lhs.updatedAt > rhs.updatedAt   // newest first within a bucket
            }
    }

    /// Lower bucket sorts first.
    static func bucket(_ thread: WorkThread) -> Int {
        let pinned = thread.isPinned
        if thread.needsAttention { return pinned ? 0 : 1 }
        if thread.isRunning { return pinned ? 2 : 3 }
        return pinned ? 4 : 5
    }

    /// The single derived state shown as the row's status chip.
    enum RowState: Equatable {
        case needsAttention
        case running
        case idle
    }

    static func rowState(_ thread: WorkThread) -> RowState {
        if thread.needsAttention { return .needsAttention }
        if thread.isRunning { return .running }
        return .idle
    }

    // MARK: - Turn presentation

    /// Map a turn's lifecycle to the shared StatusPill kind.
    static func pillKind(for status: ThreadTurnStatus) -> StatusPill.Kind {
        switch status {
        case .draft, .queued: return .queued
        case .running: return .running
        case .done: return .done
        case .failed, .cancelled: return .failed
        case .timedOut: return .timedOut
        }
    }

    /// A worker turn that is actively running shows a heartbeat + elapsed time.
    static func isLive(_ turn: ThreadTurn) -> Bool {
        turn.status == .running
    }

    /// Whole-seconds elapsed since a running turn began, for the heartbeat label.
    static func elapsedSeconds(_ turn: ThreadTurn, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(turn.createdAt)))
    }

    /// Author label for a turn header.
    static func authorLabel(_ turn: ThreadTurn) -> String {
        switch turn.author {
        case .user: return "You"
        case .worker: return turn.workerId ?? "Worker"
        case .system: return "Allnighter"
        }
    }

    /// The text a turn renders in the timeline: chat text, or the failure reason
    /// for a failed/timed-out turn (failures are turns too, shown honestly).
    static func bodyText(_ turn: ThreadTurn) -> String? {
        if let text = turn.text, !text.isEmpty { return text }
        switch turn.status {
        case .failed: return "Worker failed."
        case .timedOut: return "Worker timed out."
        case .cancelled: return "Cancelled."
        default: return nil
        }
    }

    // MARK: - Composer

    /// The composer chip copy, e.g. "Replying as worker_opus".
    static func replyingAs(workerId: String?) -> String {
        guard let workerId else { return "No worker available" }
        return "Replying as \(workerId)"
    }

    // MARK: - Context reveal (size measured in bytes — never tokens)

    static func contextSizeLabel(_ packet: ThreadContextPacket) -> String {
        "\(packet.byteCount) bytes"
    }
}
