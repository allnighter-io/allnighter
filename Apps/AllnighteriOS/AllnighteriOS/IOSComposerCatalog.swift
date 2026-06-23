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

    func workerIdForSend(continuationWorkerId: String?) -> String {
        selectedWorkerId ?? continuationWorkerId ?? ConversationAgentPresentation.previewWorkerId
    }
}

enum IOSComposerCatalog {
    static let defaultTeam = IOSComposerTeamOption(
        id: "default",
        presetId: nil,
        name: "Default Team",
        lane: nil
    )

    static let models: [IOSComposerModelOption] = [
        IOSComposerModelOption(
            id: "claude-opus-4-6#0",
            driverId: "claude_code",
            title: "Agent (Opus 4.6)"
        ),
        IOSComposerModelOption(
            id: "claude-opus-4-8#0",
            driverId: "claude_code",
            title: "Agent (Opus 4.8)"
        ),
        IOSComposerModelOption(
            id: "claude-sonnet-4-6#0",
            driverId: "claude_code",
            title: "Agent (Sonnet 4.6)"
        ),
        IOSComposerModelOption(
            id: "codex#0",
            driverId: "codex",
            title: "Agent (Codex)"
        ),
    ]

    static let teams: [IOSComposerTeamOption] = [
        defaultTeam,
        IOSComposerTeamOption(id: "code_core", presetId: "code_core", name: "Code Core", lane: .code),
        IOSComposerTeamOption(id: "copy_landing", presetId: "copy_landing_page", name: "Copy · Landing", lane: .copy),
        IOSComposerTeamOption(id: "design_board", presetId: "design_board", name: "Design Board", lane: .design),
    ]
}
