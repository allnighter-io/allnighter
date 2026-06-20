import Foundation
import SwiftUI
import AllnighterCore
import AllnighterEngine

/// Pure view-state for the Work Threads surfaces. No I/O, no SwiftUI state — so
/// triage ordering and turn presentation are unit-testable without a running
/// app. All values derive from `WorkThread` / `ThreadTurn` truth.
enum ThreadsPresenter {

    // MARK: - Thread list triage (06 + 07)

    /// Named triage bucket — lower sorts first within the active rail.
    enum ThreadTriageBucket: Int, Comparable, CaseIterable {
        case pinnedAttention
        case attention
        case pinnedUnread
        case unread
        case pinnedRunning
        case running
        case pinnedRecent
        case recent

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Section header for production rails (pinned/unpinned share a family).
        var sectionTitle: String {
            switch self {
            case .pinnedAttention, .attention: return "Attention"
            case .pinnedUnread, .unread: return "Unread"
            case .pinnedRunning, .running: return "Running"
            case .pinnedRecent, .recent: return "Recent"
            }
        }
    }

    struct ThreadTriageKey: Equatable {
        var bucket: ThreadTriageBucket
        var updatedAt: Date
    }

    /// Active rail order: pinned+attention → attention → pinned+unread → unread →
    /// pinned+running → running → pinned recent → recent (`updatedAt` desc).
    static func triagedActive(_ threads: [WorkThread]) -> [WorkThread] {
        threads
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let l = triageKey(for: lhs), r = triageKey(for: rhs)
                if l.bucket != r.bucket { return l.bucket < r.bucket }
                return l.updatedAt > r.updatedAt
            }
    }

    /// Archive view: archived threads only, `updatedAt` desc.
    static func triagedArchived(_ threads: [WorkThread]) -> [WorkThread] {
        threads.filter(\.isArchived).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Back-compat alias used by unit tests.
    static func triaged(_ threads: [WorkThread]) -> [WorkThread] {
        triagedActive(threads)
    }

    static func triageKey(for thread: WorkThread) -> ThreadTriageKey {
        ThreadTriageKey(bucket: triageBucket(for: thread), updatedAt: thread.updatedAt)
    }

    static func triageBucket(for thread: WorkThread) -> ThreadTriageBucket {
        let pinned = thread.isPinned
        if thread.needsAttention { return pinned ? .pinnedAttention : .attention }
        if thread.hasUnread { return pinned ? .pinnedUnread : .unread }
        if thread.isRunning { return pinned ? .pinnedRunning : .running }
        return pinned ? .pinnedRecent : .recent
    }

    /// Labelled sections that mirror triage families — not broad Pinned/Recent.
    struct TriageSection: Identifiable, Equatable {
        let id: String
        let title: String
        let threads: [WorkThread]
    }

    static func triageSections(
        _ threads: [WorkThread], filter: RailFilter, search: String
    ) -> [TriageSection] {
        let visible = activeRailThreads(threads, filter: filter, search: search)
        var sections: [TriageSection] = []
        var currentTitle: String?
        var currentThreads: [WorkThread] = []

        func flush() {
            guard let title = currentTitle, !currentThreads.isEmpty else { return }
            sections.append(TriageSection(id: title.lowercased(), title: title, threads: currentThreads))
        }

        for thread in visible {
            let title = triageBucket(for: thread).sectionTitle
            if title != currentTitle {
                flush()
                currentTitle = title
                currentThreads = [thread]
            } else {
                currentThreads.append(thread)
            }
        }
        flush()
        return sections
    }

    /// Triaged active list with lane filter + search.
    static func activeRailThreads(
        _ threads: [WorkThread], filter: RailFilter, search: String
    ) -> [WorkThread] {
        triagedActive(threads).filter { matches($0, filter: filter) && matchesSearch($0, query: search) }
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

    // MARK: - Unread freshness (06)

    /// Whether the row should show the unread indication light. Separate from
    /// `rowState` — attention and unread are independent axes.
    static func showsUnreadLight(_ thread: WorkThread) -> Bool {
        thread.hasUnread
    }

    /// Unread anchor that also requires user attention (failed/blocking system).
    static func unreadNeedsAttention(_ thread: WorkThread) -> Bool {
        thread.unreadNeedsAttention
    }

    static func firstUnreadTurnId(_ thread: WorkThread) -> String? {
        thread.firstUnreadTurnId
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
        case .mutatingRun where last.status == .done: return .exit0
        case .mutatingRun where last.status == .failed: return .exit1
        default: return nil
        }
    }

    // MARK: - Rail filter / search (CR4e)

    /// The rail's lane chips. `running` is a state, not a lane, but lives here so
    /// the rail filter is a single control.
    enum RailFilter: String, CaseIterable {
        case all, design, code, running
    }

    /// The lane a thread belongs to, inferred from the work it actually did (a
    /// design board → Design; a team run / mutating run → Code). A
    /// chat-only or empty thread has no lane and shows only under All.
    static func lane(of thread: WorkThread) -> ComposeLane? {
        if thread.turns.contains(where: { $0.kind == .designBoard }) { return .design }
        if thread.turns.contains(where: { $0.kind == .teamRun || $0.kind == .mutatingRun }) {
            return .code
        }
        return nil
    }

    static func matches(_ thread: WorkThread, filter: RailFilter) -> Bool {
        switch filter {
        case .all: return true
        case .design: return lane(of: thread) == .design
        case .code: return lane(of: thread) == .code
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

    /// Triaged, filtered, and searched — the flat active-rail order.
    static func railThreads(_ threads: [WorkThread], filter: RailFilter, search: String) -> [WorkThread] {
        activeRailThreads(threads, filter: filter, search: search)
    }

    // MARK: - Project grouping (PRJ-S14)

    /// One project's threads in the rail. Legacy/unbound threads are intentionally
    /// not given a visible bucket; new GUI sends must bind to a Project before they run.
    struct ProjectGroup: Identifiable, Equatable {
        let id: String
        let project: Project
        let threads: [WorkThread]
        /// Aggregate unread dot = any thread in the group is unread.
        var hasUnread: Bool { threads.contains { $0.hasUnread } }
        var title: String { project.displayName }
    }

    /// The rail rebuilt around projects: a flat cross-project Pinned section, then
    /// one group per project (active roster order). Search filters within; archived
    /// and unbound legacy threads never appear.
    static func projectSections(
        _ threads: [WorkThread], projects: [Project], search: String
    ) -> (pinned: [WorkThread], groups: [ProjectGroup]) {
        let known = Set(projects.map(\.id))
        let visible = threads.filter {
            !$0.isArchived
            && matchesSearch($0, query: search)
            && ($0.projectId.map { known.contains($0) } ?? false)
        }
        let pinned = visible.filter { $0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }
        let unpinned = visible.filter { !$0.isPinned }

        var groups: [ProjectGroup] = []
        for project in projects {
            let ts = unpinned.filter { $0.projectId == project.id }.sorted { $0.updatedAt > $1.updatedAt }
            groups.append(ProjectGroup(id: project.id, project: project, threads: ts))
        }
        return (pinned, groups)
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
