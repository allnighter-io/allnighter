//
//  ConversationHomeModels.swift
//  AllnighteriOS
//
//  Presentation snapshot for the iOS conversation home.
//

import Foundation

struct ConversationListSnapshot: Equatable, Codable {
    var pinned: [ConversationSummary]
    var projects: [ConversationProject]

    static let empty = ConversationListSnapshot(pinned: [], projects: [])

    func filtering(_ includes: (ConversationSummary) -> Bool) -> ConversationListSnapshot {
        ConversationListSnapshot(
            pinned: pinned.filter(includes),
            projects: projects.compactMap { $0.filtering(includes) }
        )
    }

    func clearingUnread(for threadId: String) -> ConversationListSnapshot {
        ConversationListSnapshot(
            pinned: pinned.map { $0.id == threadId ? $0.clearingUnread() : $0 },
            projects: projects.map { $0.clearingUnread(for: threadId) }
        )
    }
}

struct ConversationSummary: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let relativeAge: String
    let statusLabel: String?
    let isUnread: Bool
    let isPending: Bool
    let needsAttention: Bool

    func clearingUnread() -> ConversationSummary {
        ConversationSummary(
            id: id,
            title: title,
            relativeAge: relativeAge,
            statusLabel: statusLabel,
            isUnread: false,
            isPending: isPending,
            needsAttention: needsAttention
        )
    }
}

struct ConversationProject: Identifiable, Equatable, Codable {
    enum Icon: String, Equatable, Codable {
        case folder
        case inbox
    }

    let id: String
    let name: String
    let icon: Icon
    let isExpanded: Bool
    let hasUnread: Bool
    let conversations: [ConversationSummary]

    func filtering(_ includes: (ConversationSummary) -> Bool) -> ConversationProject? {
        let filteredConversations = conversations.filter(includes)
        guard !filteredConversations.isEmpty else { return nil }
        return ConversationProject(
            id: id,
            name: name,
            icon: icon,
            isExpanded: isExpanded,
            hasUnread: filteredConversations.contains { $0.isUnread },
            conversations: filteredConversations
        )
    }

    func clearingUnread(for threadId: String) -> ConversationProject {
        let conversations = self.conversations.map { $0.id == threadId ? $0.clearingUnread() : $0 }
        return ConversationProject(
            id: id,
            name: name,
            icon: icon,
            isExpanded: isExpanded,
            hasUnread: conversations.contains(where: \.isUnread),
            conversations: conversations
        )
    }
}

#if DEBUG
enum ConversationHomePreviewData {
    static let snapshot = ConversationListSnapshot(
        pinned: [
            ConversationSummary(
                id: "pinned-cat",
                title: "Give me a picture of a cat",
                relativeAge: "3 days ago",
                statusLabel: nil,
                isUnread: false,
                isPending: false,
                needsAttention: false
            )
        ],
        projects: [
            ConversationProject(
                id: "allnighter",
                name: "Allnighter",
                icon: .folder,
                isExpanded: false,
                hasUnread: true,
                conversations: []
            ),
            ConversationProject(
                id: "x",
                name: "X",
                icon: .folder,
                isExpanded: false,
                hasUnread: true,
                conversations: []
            ),
            ConversationProject(
                id: "unassigned",
                name: "Unassigned",
                icon: .inbox,
                isExpanded: true,
                hasUnread: false,
                conversations: [
                    ConversationSummary(
                        id: "new-work-order-1",
                        title: "New work order",
                        relativeAge: "3 days ago",
                        statusLabel: nil,
                        isUnread: false,
                        isPending: false,
                        needsAttention: false
                    ),
                    ConversationSummary(
                        id: "say-hi-only",
                        title: "Please say hi only and nothing else",
                        relativeAge: "4 days ago",
                        statusLabel: nil,
                        isUnread: false,
                        isPending: false,
                        needsAttention: false
                    ),
                    ConversationSummary(
                        id: "say-hi-nothing-else",
                        title: "Say hi. Nothing else.",
                        relativeAge: "4 days ago",
                        statusLabel: nil,
                        isUnread: false,
                        isPending: false,
                        needsAttention: false
                    ),
                    ConversationSummary(
                        id: "new-work-order-2",
                        title: "New work order",
                        relativeAge: "4 days ago",
                        statusLabel: nil,
                        isUnread: false,
                        isPending: false,
                        needsAttention: false
                    ),
                    ConversationSummary(
                        id: "follow-up-plan",
                        title: "Follow up on the run plan",
                        relativeAge: "5 days ago",
                        statusLabel: nil,
                        isUnread: false,
                        isPending: false,
                        needsAttention: false
                    )
                ]
            )
        ]
    )
}
#endif
