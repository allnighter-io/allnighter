//
//  IOSComposerCatalog.swift
//  AllnighteriOS
//
//  Compose options for the remote chat MVP — sourced from Core catalogs (preview
//  defaults; live Mac still authoritative at run time).
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
    /// Common bench models — same ids the Mac composer uses.
    private static let modelIDs: [String] = [
        "model_opus",
        "model_sonnet",
        "model_chatgpt",
        "model_grok",
        "model_cursor_composer_25",
        "model_gemini",
    ]

    private static let teamPresetIDs: [String] = [
        "code_core",
        "copy_landing_page",
        "design_board",
    ]

    static var defaultTeam: IOSComposerTeamOption {
        let preset = TeamCatalog.defaultRunTeam()
        return IOSComposerTeamOption(
            id: "default",
            presetId: preset?.id ?? "default_chat",
            name: preset?.displayName ?? "Auto",
            lane: preset?.lane ?? .code
        )
    }

    static var models: [IOSComposerModelOption] {
        modelIDs.compactMap { id in
            guard let definition = ModelCatalog.get(id) else { return nil }
            return IOSComposerModelOption(
                id: definition.id,
                driverId: definition.driverId,
                title: definition.displayName
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static var teams: [IOSComposerTeamOption] {
        let others: [IOSComposerTeamOption] = teamPresetIDs.compactMap { id in
            guard let team = BuiltInTeams.team(id) else { return nil }
            return IOSComposerTeamOption(
                id: id,
                presetId: id,
                name: team.displayName,
                lane: team.lane
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return [defaultTeam] + others
    }
}
