import Foundation
import AllnighterCore

/// A lightweight, value-type rail-row summary (PERF-S02/S03). The sidebar renders THESE,
/// not full `WorkThread`s — so a live streaming delta (which mutates the selected thread's
/// turn text) does not invalidate every rail row, and search/state derivations are
/// computed ONCE per reload instead of walking turn arrays on every render.
struct ThreadRailRowState: Identifiable, Equatable {
    let id: String
    let projectId: String?
    let title: String
    let updatedAt: Date
    let isPinned: Bool
    let isArchived: Bool
    // Thread-only facts feeding the row's single display state (the `pending` axis is GUI
    // state — an armed Pending item — so it's combined at render, not stored here).
    let isRunning: Bool
    let hasUnread: Bool
    let hasNeverRun: Bool
    let lane: ComposeLane?
    /// Lowercased title + turn text, precomputed once so search is a substring check
    /// instead of an O(turns) walk per keystroke per row.
    let searchText: String

    /// The four-state row dot, combining the precomputed thread facts with the live
    /// armed-Pending GUI fact (same precedence as `ThreadStateDerivation`).
    func displayState(armedPending: Bool) -> ThreadDisplayState {
        if isRunning { return .running }
        if armedPending { return .pending }
        if hasUnread { return .replied }
        if hasNeverRun { return .draft }
        return .idle
    }

    func matchesSearch(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty || searchText.contains(q)
    }
}

extension ThreadsPresenter {
    /// Build a rail-row summary from a full thread — the once-per-reload derivation point.
    static func railRow(from thread: WorkThread) -> ThreadRailRowState {
        var search = thread.title.lowercased()
        for turn in thread.turns where !(turn.text ?? "").isEmpty {
            search += "\n" + (turn.text ?? "").lowercased()
        }
        return ThreadRailRowState(
            id: thread.id,
            projectId: thread.projectId,
            title: thread.title,
            updatedAt: thread.updatedAt,
            isPinned: thread.isPinned,
            isArchived: thread.isArchived,
            isRunning: thread.isRunning,
            hasUnread: thread.hasUnread,
            hasNeverRun: thread.hasNeverRun,
            lane: lane(of: thread),
            searchText: search
        )
    }

    /// One project's rail rows.
    struct ProjectRowGroup: Identifiable, Equatable {
        let id: String
        let project: Project
        let rows: [ThreadRailRowState]
        var hasUnread: Bool { rows.contains { $0.hasUnread } }
        var title: String { project.displayName }
    }

    /// The project-grouped rail over row summaries (PERF-S02): a flat cross-project Pinned
    /// section, then one group per project (active roster order). Same shape/rules as the
    /// full-thread `projectSections`, but reads only summaries.
    static func projectSections(
        _ rows: [ThreadRailRowState], projects: [Project], search: String
    ) -> (pinned: [ThreadRailRowState], groups: [ProjectRowGroup]) {
        let known = Set(projects.map(\.id))
        let visible = rows.filter {
            !$0.isArchived
            && $0.matchesSearch(search)
            && ($0.projectId.map { known.contains($0) } ?? false)
        }
        let pinned = visible.filter { $0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }
        // A pinned thread lives ONLY in the Pinned section — never also under its project group
        // (no double rows). Exclude by id so it can't reappear even if a stale summary disagrees
        // on isPinned.
        let pinnedIDs = Set(pinned.map(\.id))
        let unpinned = visible.filter { !$0.isPinned && !pinnedIDs.contains($0.id) }
        let groups = projects.map { project in
            ProjectRowGroup(
                id: project.id, project: project,
                rows: unpinned.filter { $0.projectId == project.id }.sorted { $0.updatedAt > $1.updatedAt })
        }
        return (pinned, groups)
    }
}
