//
//  IOSComposerCatalog.swift
//  AllnighteriOS
//
//  Static compose options for the remote chat MVP (preview + live defaults).
//

import AllnighterCore
import Foundation

struct IOSComposerModelOption: Identifiable, Equatable, Sendable {
    var id: String
    var driverId: String
    var title: String
}

struct IOSComposerTeamOption: Identifiable, Equatable, Sendable {
    var id: String
    var presetId: String?
    var name: String
    var lane: WorkLane?
}

struct IOSComposerDraft: Equatable, Sendable {
    var selectedWorkerId: String?
    var selectedTeamId: String = IOSComposerCatalog.defaultTeam.id
    var effort: EffortLevel = .med

    var selectedModel: IOSComposerModelOption? {
        guard let selectedWorkerId else { return nil }
        return IOSComposerCatalog.models.first { $0.id == selectedWorkerId }
    }

    var selectedTeam: IOSComposerTeamOption {
        IOSComposerCatalog.teams.first { $0.id == selectedTeamId } ?? IOSComposerCatalog.defaultTeam
    }

    /// Bench model id for the sealed remote payload; nil leaves Auto resolution to the Mac.
    func modelIdForSend(continuationWorkerId: String?) -> String? {
        if let selectedWorkerId { return selectedWorkerId }
        if let continuationWorkerId {
            return ConversationAgentPresentation.modelId(fromWorkerId: continuationWorkerId)
        }
        return nil
    }

    /// Worker instance id for optimistic transcript rows and display continuity.
    func workerIdForSend(continuationWorkerId: String?) -> String {
        if let modelId = modelIdForSend(continuationWorkerId: continuationWorkerId) {
            return ConversationAgentPresentation.workerInstanceId(for: modelId)
        }
        return continuationWorkerId ?? ConversationAgentPresentation.previewWorkerId
    }
}

enum IOSComposerCatalog {
    static let defaultTeam = IOSComposerTeamOption(
        id: "default",
        presetId: "default_chat",
        name: "Auto",
        lane: .code
    )

    static let models: [IOSComposerModelOption] = [
        IOSComposerModelOption(
            id: "model_opus",
            driverId: "claude_code",
            title: "Agent (Opus 4.8)"
        ),
        IOSComposerModelOption(
            id: "model_sonnet",
            driverId: "claude_code",
            title: "Agent (Sonnet 4.6)"
        ),
        IOSComposerModelOption(
            id: "model_chatgpt",
            driverId: "codex",
            title: "Agent (ChatGPT 5.5)"
        ),
        IOSComposerModelOption(
            id: "model_grok",
            driverId: "grok",
            title: "Agent (Grok)"
        ),
    ]

    static let teams: [IOSComposerTeamOption] = [
        defaultTeam,
        IOSComposerTeamOption(id: "code_core", presetId: "code_core", name: "Code Core", lane: .code),
        IOSComposerTeamOption(id: "copy_landing", presetId: "copy_landing_page", name: "Copy · Landing", lane: .copy),
        IOSComposerTeamOption(id: "design_board", presetId: "design_board", name: "Design Board", lane: .design),
    ]
}
