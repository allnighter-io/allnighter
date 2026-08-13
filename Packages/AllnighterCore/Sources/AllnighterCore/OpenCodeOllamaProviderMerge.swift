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
            }
        }
    }

    public struct Result: Equatable, Sendable {
        public var addedProvider: Bool
        public var filledBaseURL: Bool
        public var addedEnabledProvider: Bool

        public var didChange: Bool {
            addedProvider || filledBaseURL || addedEnabledProvider
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
    public static func merge(into root: inout [String: Any]) throws -> Result {
        var addedProvider = false
        var filledBaseURL = false
        var addedEnabledProvider = false

        var provider: [String: Any]
        if let existing = root["provider"] {
            guard let object = existing as? [String: Any] else {
                throw Error.providerMustBeObject
            }
            provider = object
        } else {
            provider = [:]
        }

        if let existingOllama = provider[providerId] {
            guard var ollama = existingOllama as? [String: Any] else {
                throw Error.ollamaProviderMustBeObject
            }
            filledBaseURL = fillBaseURLIfMissing(in: &ollama)
            provider[providerId] = ollama
        } else {
            provider[providerId] = ollamaProviderTemplate()
            addedProvider = true
        }
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
            addedEnabledProvider: addedEnabledProvider
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
        return Inspection(
            ollamaProviderPresent: ollama != nil,
            ollamaBaseURL: baseURL,
            enabledProviders: enabledStrings,
            ollamaInEnabledProviders: allowlistPresent ? ollamaInAllowlist : nil,
            wired: wired
        )
    }

    public struct Inspection: Equatable, Sendable {
        public var ollamaProviderPresent: Bool
        public var ollamaBaseURL: String?
        public var enabledProviders: [String]?
        public var ollamaInEnabledProviders: Bool?
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
}
