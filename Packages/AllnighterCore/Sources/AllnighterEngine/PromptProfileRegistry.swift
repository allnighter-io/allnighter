import Foundation
import AllnighterCore

/// The built-in prompt profiles, grouped so RB2 (review lenses) and RB3 (final
/// spec) append their own without a parallel store. The two judge profiles are
/// the Phase 06 synthesis instructions, generalized into `PromptProfile`s.
public enum BuiltInProfiles {
    public static var judgeAnalysis: PromptProfile {
        PromptProfile(id: SynthesisInstructions.analysisID, displayName: "Judge — Analysis",
                      purpose: .judgeAnalysis, template: SynthesisInstructions.analysisText, builtIn: true)
    }
    public static var judgePlan: PromptProfile {
        PromptProfile(id: SynthesisInstructions.planID, displayName: "Judge — Master Plan",
                      purpose: .judgePlan, template: SynthesisInstructions.planText, builtIn: true)
    }

    /// Return-review profile (RB5): advisory evaluation of an execution return.
    public static var returnReview: PromptProfile {
        PromptProfile(
            id: "return_review_v1", displayName: "Return Review", purpose: .returnReview,
            template: "You are evaluating an executor's work against the spec it was given. Be specific and advisory; do not edit the executor's output.",
            builtIn: true
        )
    }

    /// All built-in profiles. RB2 adds `reviewLenses`; RB3 adds `finalSpec`;
    /// RB5 adds `returnReview`.
    public static var all: [PromptProfile] {
        [judgeAnalysis, judgePlan] + reviewLenses + [finalSpec, returnReview]
    }
}

/// File-backed registry of prompt profiles (built-ins + user) under
/// `Config/PromptProfiles/`. Generalizes `SynthesisInstructionStore`.
public struct PromptProfileStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
            ?? AllnighterPaths.config.appendingPathComponent("PromptProfiles", isDirectory: true)
    }

    public func load() -> [PromptProfile] {
        var byID: [String: PromptProfile] = [:]
        var order: [String] = []
        for profile in BuiltInProfiles.all where byID[profile.id] == nil {
            byID[profile.id] = profile
            order.append(profile.id)
        }
        for profile in userProfiles() {
            if byID[profile.id] == nil { order.append(profile.id) }
            byID[profile.id] = profile
        }
        return order.compactMap { byID[$0] }
    }

    public func profile(id: String) -> PromptProfile? { load().first { $0.id == id } }

    public func profiles(purpose: PromptProfile.Purpose) -> [PromptProfile] {
        load().filter { $0.purpose == purpose }
    }

    @discardableResult
    public func save(_ profile: PromptProfile) throws -> URL {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let url = rootDirectory.appendingPathComponent("\(profile.id).json")
        try CoreJSON.encode(profile).write(to: url)
        return url
    }

    public func delete(id: String) throws {
        let url = rootDirectory.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func userProfiles() -> [PromptProfile] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) else { return [] }
        return entries
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? CoreJSON.decode(PromptProfile.self, from: Data(contentsOf: $0)) }
    }
}

/// File-backed registry of user workflow presets under `Config/WorkflowPresets/`.
public struct WorkflowPresetStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
            ?? AllnighterPaths.config.appendingPathComponent("WorkflowPresets", isDirectory: true)
    }

    public func load() -> [WorkflowPreset] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) else { return [] }
        return entries
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? CoreJSON.decode(WorkflowPreset.self, from: Data(contentsOf: $0)) }
    }

    @discardableResult
    public func save(_ preset: WorkflowPreset) throws -> URL {
        try preset.validate()
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let url = rootDirectory.appendingPathComponent("\(preset.id).json")
        try CoreJSON.encode(preset).write(to: url)
        return url
    }

    public func delete(id: String) throws {
        let url = rootDirectory.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
