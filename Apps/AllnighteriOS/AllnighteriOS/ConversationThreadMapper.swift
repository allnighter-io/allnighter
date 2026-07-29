//
//  ConversationThreadMapper.swift
//  AllnighteriOS
//
//  Projects Core's decrypted remote thread detail into an iOS transcript.
//

import AllnighterCore
import Foundation

struct ConversationThreadMapper {
    func snapshot(from detail: RemoteThreadDetail) -> ConversationThreadSnapshot {
        let readThroughTurnId = detail.summary.readState.latestUnreadTurnId
            ?? (detail.summary.readState.hasUnread ? detail.turns.last?.id : nil)

        return ConversationThreadSnapshot(
            id: detail.id,
            title: detail.summary.title,
            statusLabel: statusLabel(for: detail.summary.displayState),
            isActive: detail.summary.displayState == .running || detail.summary.displayState == .pending,
            hasUnread: detail.summary.readState.hasUnread,
            readThroughTurnId: readThroughTurnId,
            turns: detail.turns.map(turn(from:))
        )
    }

    private func statusLabel(for state: ThreadDisplayState) -> String? {
        switch state {
        case .running: "Running on your Mac"
        case .pending: "Queued on your Mac"
        case .replied: "Unread reply"
        case .draft: "Draft"
        case .idle: nil
        }
    }

    private func turn(from remoteTurn: RemoteThreadTurnDetail) -> ConversationThreadTurn {
        let agentInstanceId = remoteTurn.author == .worker ? remoteTurn.modelId : nil
        return ConversationThreadTurn(
            id: remoteTurn.id,
            role: role(from: remoteTurn),
            text: normalizedText(remoteTurn.text),
            runId: remoteTurn.runId,
            modelId: agentInstanceId,
            driverId: agentInstanceId.map { ConversationAgentPresentation.driverId(for: $0) },
            agentTitle: agentInstanceId.map { ConversationAgentPresentation.agentTitle(for: $0) },
            isPending: remoteTurn.status == .queued || remoteTurn.status == .running,
            isFailed: remoteTurn.status == .failed || remoteTurn.status == .timedOut,
            isTruncated: remoteTurn.partialOutputTruncated,
            hasAttachments: !remoteTurn.attachmentRefs.isEmpty,
            hasFileReferences: !remoteTurn.fileReferenceRefs.isEmpty
        )
    }

    private func role(from turn: RemoteThreadTurnDetail) -> ConversationThreadTurn.Role {
        switch turn.author {
        case .user:
            return .user
        case .worker:
            return .assistant
        case .system:
            return .system
        }
    }

    private func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
