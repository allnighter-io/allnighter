//
//  ConversationHomeModels.swift
//  AllnighteriOS
//
//  Presentation snapshot for the iOS conversation home.
//

import Foundation

struct ConversationListSnapshot: Equatable {
    var pinned: [ConversationSummary]
    var projects: [ConversationProject]

    static let empty = ConversationListSnapshot(pinned: [], projects: [])
}

struct ConversationSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let relativeAge: String
    let isUnread: Bool
    let isPending: Bool
}

struct ConversationProject: Identifiable, Equatable {
    enum Icon: Equatable {
        case folder
        case inbox
    }

    let id: String
    let name: String
    let icon: Icon
    let isExpanded: Bool
    let hasUnread: Bool
    let conversations: [ConversationSummary]
    let hiddenConversationCount: Int
}

#if DEBUG
enum ConversationHomePreviewData {
    static let snapshot = ConversationListSnapshot(
        pinned: [
            ConversationSummary(
                id: "pinned-cat",
                title: "Give me a picture of a cat",
                relativeAge: "3 days ago",
                isUnread: false,
                isPending: false
            )
        ],
        projects: [
            ConversationProject(
                id: "allnighter",
                name: "Allnighter",
                icon: .folder,
                isExpanded: false,
                hasUnread: true,
                conversations: [],
                hiddenConversationCount: 0
            ),
            ConversationProject(
                id: "x",
                name: "X",
                icon: .folder,
                isExpanded: false,
                hasUnread: true,
                conversations: [],
                hiddenConversationCount: 0
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
                        isUnread: false,
                        isPending: false
                    ),
                    ConversationSummary(
                        id: "say-hi-only",
                        title: "Please say hi only and nothing else",
                        relativeAge: "4 days ago",
                        isUnread: false,
                        isPending: false
                    ),
                    ConversationSummary(
                        id: "say-hi-nothing-else",
                        title: "Say hi. Nothing else.",
                        relativeAge: "4 days ago",
                        isUnread: false,
                        isPending: false
                    ),
                    ConversationSummary(
                        id: "new-work-order-2",
                        title: "New work order",
                        relativeAge: "4 days ago",
                        isUnread: false,
                        isPending: false
                    )
                ],
                hiddenConversationCount: 1
            )
        ]
    )
}
#endif
