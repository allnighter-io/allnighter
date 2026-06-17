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

    // MARK: - Compose routing

    /// Spec ready → Execute; everything else → Chat (re-seeded on thread switch).
    static func routingDefaultMode(for thread: WorkThread) -> ComposeMode {
        if let last = thread.turns.last(where: { $0.kind == .workOrder }), last.status == .done {
            return .exec
        }
        return .chat
    }

    /// Observed conversation status for the rail pill (facts only).
    enum ConversationStatus: Equatable {
        case running, replied, boardReady, specReady, exit0, exit1

        var label: String {
            switch self {
            case .running: return "running"
            case .replied: return "replied"
            case .boardReady: return "board ready"
            case .specReady: return "spec ready"
            case .exit0: return "exit 0"
            case .exit1: return "exit 1"
            }
        }
    }

    static func conversationStatus(for thread: WorkThread) -> ConversationStatus? {
        if thread.isRunning { return .running }
        if thread.needsAttention { return .exit1 }
        guard let last = thread.turns.last(where: { $0.kind != .userMessage && $0.kind != .userDecision }) else {
            return nil
        }
        switch last.kind {
        case .workerChat where last.status == .done: return .replied
        case .designBoard, .teamRun where last.status == .done: return .boardReady
        case .workOrder where last.status == .done: return .specReady
        case .dispatch where last.status == .done: return .exit0
        case .dispatch where last.status == .failed: return .exit1
        default: return nil
        }
    }

    /// Newest-first flat list for the home rail (CR4a; triage polish = CR4e).
    static func railThreads(_ threads: [WorkThread]) -> [WorkThread] {
        threads.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Rail filter / search / grouping (CR4e)

    /// The rail's lane chips. `running` is a state, not a lane, but lives here so
    /// the rail filter is a single control.
    enum RailFilter: String, CaseIterable {
        case all, design, build, running
    }

    /// The lane a thread belongs to, inferred from the work it actually did (a
    /// design board → Design; a team run / work order / dispatch → Build). A
    /// chat-only or empty thread has no lane and shows only under All.
    static func lane(of thread: WorkThread) -> ComposeLane? {
        if thread.turns.contains(where: { $0.kind == .designBoard }) { return .design }
        if thread.turns.contains(where: { $0.kind == .teamRun || $0.kind == .workOrder || $0.kind == .dispatch }) {
            return .build
        }
        return nil
    }

    static func matches(_ thread: WorkThread, filter: RailFilter) -> Bool {
        switch filter {
        case .all: return true
        case .design: return lane(of: thread) == .design
        case .build: return lane(of: thread) == .build
        case .running: return thread.isRunning
        }
    }

    /// Case-insensitive match over the title and any turn text — so search finds a
    /// conversation by what was actually said in it, not just its title.
    static func matchesSearch(_ thread: WorkThread, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if thread.title.lowercased().contains(q) { return true }
        return thread.turns.contains { ($0.text ?? "").lowercased().contains(q) }
    }

    /// Triaged, filtered, and searched — the flat rail order.
    static func railThreads(_ threads: [WorkThread], filter: RailFilter, search: String) -> [WorkThread] {
        triaged(threads).filter { matches($0, filter: filter) && matchesSearch($0, query: search) }
    }

    /// A labelled rail section (Pinned / Recent), in display order. Pinned floats
    /// to its own group; empty groups are omitted.
    struct RailGroup: Identifiable, Equatable {
        let id: String
        let title: String
        let threads: [WorkThread]
    }

    static func railGroups(_ threads: [WorkThread], filter: RailFilter, search: String) -> [RailGroup] {
        let visible = railThreads(threads, filter: filter, search: search)
        let pinned = visible.filter(\.isPinned)
        let recent = visible.filter { !$0.isPinned }
        var groups: [RailGroup] = []
        if !pinned.isEmpty { groups.append(RailGroup(id: "pinned", title: "Pinned", threads: pinned)) }
        if !recent.isEmpty { groups.append(RailGroup(id: "recent", title: "Recent", threads: recent)) }
        return groups
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

    /// The composer chip copy, e.g. "Replying as model_opus".
    static func replyingAs(workerId: String?) -> String {
        guard let workerId else { return "No worker available" }
        return "Replying as \(workerId)"
    }

    // MARK: - Context reveal (size measured in bytes — never tokens)

    static func contextSizeLabel(_ packet: ThreadContextPacket) -> String {
        "\(packet.byteCount) bytes"
    }
}
