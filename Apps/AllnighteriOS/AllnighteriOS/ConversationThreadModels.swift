//
//  ConversationThreadModels.swift
//  AllnighteriOS
//
//  Presentation snapshot for a decrypted remote thread.
//

import Foundation

struct ConversationThreadSnapshot: Equatable, Codable {
    var id: String
    var title: String
    var statusLabel: String?
    var isActive: Bool
    var hasUnread: Bool
    var readThroughTurnId: String?
    var turns: [ConversationThreadTurn]

    var activeRunId: String? {
        turns.last(where: \.isPending)?.runId
    }

    var latestOutput: String? {
        turns.last(where: { ($0.text?.isEmpty == false) && ($0.role == .assistant || $0.role == .system) })?.text
    }
}

struct ConversationThreadTurn: Identifiable, Equatable, Codable {
    enum Role: String, Equatable, Codable {
        case user
        case assistant
        case system
    }

    let id: String
    let role: Role
    let text: String?
    let runId: String?
    let workerId: String?
    let driverId: String?
    let agentTitle: String?
    let isPending: Bool
    let isFailed: Bool
    let isTruncated: Bool
    let hasAttachments: Bool
    let hasFileReferences: Bool
}
