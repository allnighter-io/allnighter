//
//  ConversationAgentPresentation.swift
//  AllnighteriOS
//
//  Worker / driver labels for thread transcript + composer continuity.
//

import Foundation

enum ConversationAgentPresentation {
    static let previewWorkerId = "claude-opus-4-6#0"

    static func driverId(for workerId: String?) -> String {
        guard let workerId else { return "claude_code" }
        let modelPart = modelPart(from: workerId).lowercased()
        if modelPart.contains("claude") { return "claude_code" }
        if modelPart.contains("codex") || modelPart.contains("gpt") || modelPart.contains("openai") {
            return "codex"
        }
        if modelPart.contains("grok") { return "grok" }
        if modelPart.contains("gemini") || modelPart.contains("antigravity") { return "antigravity" }
        if modelPart.contains("cursor") { return "cursor_agent" }
        return "claude_code"
    }

    static func modelDisplayName(for workerId: String?) -> String {
        guard let workerId else { return "Agent" }
        let modelPart = modelPart(from: workerId).lowercased()
        if let opus = opusLabel(from: modelPart) { return opus }
        if modelPart.contains("sonnet") { return "Sonnet" }
        if modelPart.contains("haiku") { return "Haiku" }
        if modelPart.contains("grok") { return "Grok" }
        if modelPart.contains("codex") { return "Codex" }
        if modelPart.contains("gemini") { return "Gemini" }
        if modelPart.contains("cursor") { return "Cursor" }
        return modelPart
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    static func agentTitle(for workerId: String?) -> String {
        "Agent (\(modelDisplayName(for: workerId)))"
    }

    private static func modelPart(from workerId: String) -> String {
        workerId.split(separator: "#").first.map(String.init) ?? workerId
    }

    private static func opusLabel(from modelPart: String) -> String? {
        guard modelPart.contains("opus") else { return nil }
        let pieces = modelPart.split(separator: "-").map(String.init)
        guard let opusIndex = pieces.firstIndex(where: { $0 == "opus" }),
              opusIndex + 1 < pieces.count else {
            return "Opus"
        }
        let version = pieces[(opusIndex + 1)...]
            .joined(separator: ".")
            .replacingOccurrences(of: "_", with: ".")
        return version.isEmpty ? "Opus" : "Opus \(version)"
    }

    static func composerChipTitle(for workerId: String?) -> String {
        guard let workerId else { return "Auto" }
        return modelDisplayName(for: workerId)
    }

    static func composerChipTitle(fromAgentTitle title: String) -> String {
        title
            .replacingOccurrences(of: "Agent (", with: "")
            .replacingOccurrences(of: ")", with: "")
    }
}
