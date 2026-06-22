//
//  ConversationHomeMapper.swift
//  AllnighteriOS
//
//  Projects Core's remote thread list into the iOS home presentation shape.
//

import AllnighterCore
import Foundation

struct ConversationHomeMapper {
    var projectNames: [String: String] = [:]

    func snapshot(
        from envelope: RemoteThreadSnapshotEnvelope,
        now: Date = Date()
    ) -> ConversationListSnapshot {
        let activeThreads = envelope.threads.filter { $0.status != .archived }
        let pinned = activeThreads
            .filter { $0.pinnedAt != nil }
            .sorted(by: pinnedSort)
            .map { summary($0, now: now) }

        let unpinned = activeThreads
            .filter { $0.pinnedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }

        return ConversationListSnapshot(
            pinned: pinned,
            projects: groupedProjects(from: unpinned, now: now)
        )
    }

    private func groupedProjects(
        from threads: [RemoteThreadSummary],
        now: Date
    ) -> [ConversationProject] {
        let grouped = Dictionary(grouping: threads) { $0.projectId }
        let projectIds = grouped.keys
            .compactMap { $0 }
            .sorted { projectName(for: $0).localizedCaseInsensitiveCompare(projectName(for: $1)) == .orderedAscending }

        let namedProjects = projectIds.compactMap { projectId -> ConversationProject? in
            guard let threads = grouped[projectId] else { return nil }
            return project(
                id: projectId,
                name: projectName(for: projectId),
                icon: .folder,
                isExpanded: false,
                threads: threads,
                now: now
            )
        }

        guard let unassignedThreads = grouped[nil], !unassignedThreads.isEmpty else {
            return namedProjects
        }

        return namedProjects + [
            project(
                id: "unassigned",
                name: "Unassigned",
                icon: .inbox,
                isExpanded: true,
                threads: unassignedThreads,
                now: now
            )
        ]
    }

    private func project(
        id: String,
        name: String,
        icon: ConversationProject.Icon,
        isExpanded: Bool,
        threads: [RemoteThreadSummary],
        now: Date
    ) -> ConversationProject {
        let sortedThreads = threads.sorted { $0.updatedAt > $1.updatedAt }

        return ConversationProject(
            id: id,
            name: name,
            icon: icon,
            isExpanded: isExpanded,
            hasUnread: sortedThreads.contains { $0.readState.hasUnread },
            conversations: sortedThreads.map { summary($0, now: now) }
        )
    }

    private func summary(_ thread: RemoteThreadSummary, now: Date) -> ConversationSummary {
        ConversationSummary(
            id: thread.id,
            title: thread.title,
            relativeAge: relativeAge(from: thread.updatedAt, now: now),
            isUnread: thread.readState.hasUnread,
            isPending: thread.displayState == .pending || thread.displayState == .running
        )
    }

    private func projectName(for projectId: String) -> String {
        projectNames[projectId] ?? projectId
    }

    private func pinnedSort(_ lhs: RemoteThreadSummary, _ rhs: RemoteThreadSummary) -> Bool {
        switch (lhs.pinnedAt, rhs.pinnedAt) {
        case let (left?, right?):
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func relativeAge(from date: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        let minute = 60
        let hour = 60 * minute
        let day = 24 * hour

        if elapsed < minute { return "just now" }
        if elapsed < hour { return unit(elapsed / minute, singular: "minute") }
        if elapsed < day { return unit(elapsed / hour, singular: "hour") }
        return unit(elapsed / day, singular: "day")
    }

    private func unit(_ value: Int, singular: String) -> String {
        "\(value) \(singular)\(value == 1 ? "" : "s") ago"
    }
}
