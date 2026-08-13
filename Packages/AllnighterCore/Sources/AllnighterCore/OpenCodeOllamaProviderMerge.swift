import Foundation

/// Additive merge of local Ollama into an OpenCode `opencode.json` object.
///
/// Never replaces `enabled_providers`. Missing allowlist stays missing (creating
/// `["ollama"]` would drop implicit `opencode-go`). Existing keys stay put.
public enum OpenCodeOllamaProviderMerge {
    public static let providerId = "ollama"
    public static let goProviderId = "opencode-go"
    public static let defaultBaseURL = "http://localhost:11434/v1"
    public static let npmPackage = "@ai-sdk/openai-compatible"
    public static let providerDisplayName = "Ollama (local)"

    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case rootMustBeObject
        case providerMustBeObject
        case enabledProvidersMustBeArray
        case ollamaProviderMustBeObject
        case ollamaModelsMustBeObject

        public var description: String {
            switch self {
            case .rootMustBeObject:
                return "opencode.json root must be a JSON object — refusing to clobber it"
            case .providerMustBeObject:
                return "opencode.json `provider` must be a JSON object — refusing to clobber it"
            case .enabledProvidersMustBeArray:
                return "opencode.json `enabled_providers` must be a JSON array — refusing to clobber it"
            case .ollamaProviderMustBeObject:
                return "opencode.json `provider.ollama` must be a JSON object — refusing to clobber it"
            case .ollamaModelsMustBeObject:
                return "opencode.json `provider.ollama.models` must be a JSON object — refusing to clobber it"
            }
        }
    }

    public struct Result: Equatable, Sendable {
        public var addedProvider: Bool
        public var filledBaseURL: Bool
        public var addedEnabledProvider: Bool
        public var addedModelIds: [String]
        public var createdModelsMap: Bool

        public init(
            addedProvider: Bool,
            filledBaseURL: Bool,
            addedEnabledProvider: Bool,
            addedModelIds: [String] = [],
            createdModelsMap: Bool = false
        ) {
            self.addedProvider = addedProvider
            self.filledBaseURL = filledBaseURL
            self.addedEnabledProvider = addedEnabledProvider
            self.addedModelIds = addedModelIds
            self.createdModelsMap = createdModelsMap
        }

        public var didChange: Bool {
            addedProvider || filledBaseURL || addedEnabledProvider
                || !addedModelIds.isEmpty || createdModelsMap
        }
    }

    public static func ollamaProviderTemplate() -> [String: Any] {
        [
            "npm": npmPackage,
            "name": providerDisplayName,
            "options": [
                "baseURL": defaultBaseURL,
            ] as [String: Any],
        ]
    }

    public static func parseRoot(_ data: Data) throws -> [String: Any] {
        if data.isEmpty { return [:] }
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let root = obj as? [String: Any] else {
            throw Error.rootMustBeObject
        }
        return root
    }

    public static func encodeRoot(_ root: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        data.append(contentsOf: [0x0A])
        return data
    }

    /// Mutates `root` in place. Returns what was added — never deletes.
    /// `localTags` are Ollama `/api/tags` names; missing keys are inserted
    /// under `provider.ollama.models`. Existing model entries are never
    /// rewritten. Empty tags register nothing.
    public static func merge(
        into root: inout [String: Any],
        localTags: [String] = []
    ) throws -> Result {
        var addedProvider = false
        var filledBaseURL = false
        var addedEnabledProvider = false
        var addedModelIds: [String] = []
        var createdModelsMap = false

        var provider: [String: Any]
        if let existing = root["provider"] {
            guard let object = existing as? [String: Any] else {
                throw Error.providerMustBeObject
            }
            provider = object
        } else {
            provider = [:]
        }

        var ollama: [String: Any]
        if let existingOllama = provider[providerId] {
            guard let object = existingOllama as? [String: Any] else {
                throw Error.ollamaProviderMustBeObject
            }
            ollama = object
            filledBaseURL = fillBaseURLIfMissing(in: &ollama)
        } else {
            ollama = ollamaProviderTemplate()
            addedProvider = true
        }
        let modelMerge = try registerMissingModels(in: &ollama, tags: localTags)
        addedModelIds = modelMerge.addedIds
        createdModelsMap = modelMerge.createdMap
        provider[providerId] = ollama
        root["provider"] = provider

        if let existing = root["enabled_providers"] {
            guard var list = existing as? [Any] else {
                throw Error.enabledProvidersMustBeArray
            }
            let already = list.contains { ($0 as? String) == providerId }
            if !already {
                list.append(providerId)
                addedEnabledProvider = true
            }
            root["enabled_providers"] = list
        }

        return Result(
            addedProvider: addedProvider,
            filledBaseURL: filledBaseURL,
            addedEnabledProvider: addedEnabledProvider,
            addedModelIds: addedModelIds,
            createdModelsMap: createdModelsMap
        )
    }

    public static func inspect(_ root: [String: Any]) -> Inspection {
        let provider = root["provider"] as? [String: Any]
        let ollama = provider?[providerId] as? [String: Any]
        let options = ollama?["options"] as? [String: Any]
        let baseURL = options?["baseURL"] as? String
        let enabled = root["enabled_providers"] as? [Any]
        let enabledStrings = enabled?.compactMap { $0 as? String }
        let ollamaInAllowlist = enabledStrings?.contains(providerId) ?? false
        let allowlistPresent = enabled != nil
        let wired = ollama != nil && (!allowlistPresent || ollamaInAllowlist)
        let modelIds = (ollama?["models"] as? [String: Any]).map { Array($0.keys).sorted() }
        return Inspection(
            ollamaProviderPresent: ollama != nil,
            ollamaBaseURL: baseURL,
            enabledProviders: enabledStrings,
            ollamaInEnabledProviders: allowlistPresent ? ollamaInAllowlist : nil,
            ollamaModelIds: modelIds,
            wired: wired
        )
    }

    public struct Inspection: Equatable, Sendable {
        public var ollamaProviderPresent: Bool
        public var ollamaBaseURL: String?
        public var enabledProviders: [String]?
        public var ollamaInEnabledProviders: Bool?
        public var ollamaModelIds: [String]?
        public var wired: Bool
    }

    static func fillBaseURLIfMissing(in ollama: inout [String: Any]) -> Bool {
        if let existing = ollama["options"] {
            guard var options = existing as? [String: Any] else { return false }
            if options["baseURL"] == nil {
                options["baseURL"] = defaultBaseURL
                ollama["options"] = options
                return true
            }
            return false
        }
        ollama["options"] = ["baseURL": defaultBaseURL]
        return true
    }

    public static func modelEntry(for tag: String) -> [String: Any] {
        ["name": tag]
    }

    /// Remove only `ids` from `provider.ollama.models`. Never rewrites remaining
    /// entries. Drops an empty models map only when this setup created it.
    public static func removeAddedModels(
        from root: inout [String: Any],
        ids: [String],
        dropEmptyMap: Bool
    ) {
        guard !ids.isEmpty,
              var provider = root["provider"] as? [String: Any],
              var ollama = provider[providerId] as? [String: Any],
              var models = ollama["models"] as? [String: Any]
        else { return }
        for id in ids {
            models.removeValue(forKey: id)
        }
        if models.isEmpty, dropEmptyMap {
            ollama.removeValue(forKey: "models")
        } else {
            ollama["models"] = models
        }
        provider[providerId] = ollama
        root["provider"] = provider
    }

    private static func registerMissingModels(
        in ollama: inout [String: Any],
        tags: [String]
    ) throws -> (addedIds: [String], createdMap: Bool) {
        let uniqueTags = uniquedNonEmpty(tags)
        if uniqueTags.isEmpty { return ([], false) }

        var createdMap = false
        var models: [String: Any]
        if let existing = ollama["models"] {
            guard let object = existing as? [String: Any] else {
                throw Error.ollamaModelsMustBeObject
            }
            models = object
        } else {
            models = [:]
            createdMap = true
        }

        var addedIds: [String] = []
        for tag in uniqueTags {
            if models[tag] != nil { continue }
            models[tag] = modelEntry(for: tag)
            addedIds.append(tag)
        }
        if addedIds.isEmpty {
            return ([], false)
        }
        ollama["models"] = models
        return (addedIds, createdMap)
    }

    private static func uniquedNonEmpty(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in tags {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            out.append(tag)
        }
        return out
    }
}
