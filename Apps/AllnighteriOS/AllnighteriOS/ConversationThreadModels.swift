//
//  ConversationThreadModels.swift
//  AllnighteriOS
//
//  Presentation snapshot for a decrypted remote thread.
//

import Foundation

struct ConversationThreadSnapshot: Equatable {
    var id: String
    var title: String
    var turns: [ConversationThreadTurn]
}

struct ConversationThreadTurn: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case system
    }

    let id: String
    let role: Role
    let text: String?
    let isPending: Bool
    let isFailed: Bool
    let isTruncated: Bool
    let hasAttachments: Bool
    let hasFileReferences: Bool
}
