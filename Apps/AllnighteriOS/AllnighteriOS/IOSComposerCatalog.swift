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
    var selectedModelId: String?
    var selectedTeamId: String = IOSComposerCatalog.defaultTeam.id
    var effort: EffortLevel = .med

    var selectedModel: IOSComposerModelOption? {
        guard let selectedModelId else { return nil }
        return IOSComposerCatalog.models.first { $0.id == selectedModelId }
    }

    var selectedTeam: IOSComposerTeamOption {
        IOSComposerCatalog.teams.first { $0.id == selectedTeamId } ?? IOSComposerCatalog.defaultTeam
    }

    /// Bench model id for the sealed remote payload; nil leaves Auto resolution to the Mac.
    func modelIdForSend(continuationModelId: String?) -> String? {
        if let selectedModelId { return selectedModelId }
        if let continuationModelId {
            return ConversationAgentPresentation.modelId(fromAgentInstanceId: continuationModelId)
        }
        return nil
    }

    /// Agent instance id for optimistic transcript rows and display continuity.
    func agentInstanceIdForSend(continuationModelId: String?) -> String {
        if let modelId = modelIdForSend(continuationModelId: continuationModelId) {
            return ConversationAgentPresentation.workerInstanceId(for: modelId)
        }
        return continuationModelId ?? ConversationAgentPresentation.previewAgentInstanceId
    }
}

enum IOSComposerCatalog {
    /// Common bench models — same ids the Mac composer uses.
    private static let modelIDs: [String] = [
        "model_opus",
        "model_sonnet",
        "model_gpt_sol",
        "model_grok",
        "model_cursor_composer_25",
        "model_cursor_grok_45",
        "model_cursor_grok_46",
        "model_gemini",
    ]

    private static let teamPresetIDs: [String] = [
        "code_plan",
        "copy_landing",
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
