import Foundation

/// Backup + apply + undo for OpenCode's `opencode.json`.
///
/// Callers pass explicit URLs. This type never defaults to
/// `~/.config/opencode/opencode.json` — the CLI resolves that path and must
/// refuse it under XCTest.
public enum OpenCodeOllamaSetup {
    public static let backupInfix = "bak-alln-ocl-s02a"
    public static let undoCommand = "alln opencode-local undo"
    public static let setupCommand = "alln opencode-local setup"

    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case testHostRefusedRealConfig(String)
        case invalidJSON(String)
        case merge(OpenCodeOllamaProviderMerge.Error)
        case missingReceipt
        case receiptMismatch(String)
        case io(String)

        public var description: String {
            switch self {
            case .testHostRefusedRealConfig(let path):
                return "refusing to touch the real OpenCode config under XCTest: \(path)"
            case .invalidJSON(let detail):
                return "opencode.json is not valid JSON (\(detail)) — refusing to clobber it"
            case .merge(let error):
                return error.description
            case .missingReceipt:
                return "no setup receipt — cannot undo safely. Restore the `.\(OpenCodeOllamaSetup.backupInfix)-*` backup next to opencode.json if you still have it"
            case .receiptMismatch(let detail):
                return "setup receipt does not match this config file (\(detail))"
            case .io(let detail):
                return detail
            }
        }
    }

    public struct Receipt: Codable, Equatable, Sendable {
        public var schema: String
        public var configPath: String
        public var backupPath: String?
        public var addedProvider: Bool
        public var filledBaseURL: Bool
        public var addedEnabledProvider: Bool
        public var appliedAt: String

        public static let schemaId = "alln.opencode-ollama-setup.v1"

        public init(
            schema: String = schemaId,
            configPath: String,
            backupPath: String?,
            addedProvider: Bool,
            filledBaseURL: Bool,
            addedEnabledProvider: Bool,
            appliedAt: String
        ) {
            self.schema = schema
            self.configPath = configPath
            self.backupPath = backupPath
            self.addedProvider = addedProvider
            self.filledBaseURL = filledBaseURL
            self.addedEnabledProvider = addedEnabledProvider
            self.appliedAt = appliedAt
        }
    }

    public struct Report: Codable, Equatable, Sendable {
        public var action: String
        public var configPath: String
        public var backupPath: String?
        public var wrote: Bool
        public var addedProvider: Bool
        public var filledBaseURL: Bool
        public var addedEnabledProvider: Bool
        public var alreadyWired: Bool
        public var wired: Bool
        public var enabledProviders: [String]?
        public var ollamaBaseURL: String?
        public var undoCommand: String
        public var message: String
    }

    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/opencode.json")
    }

    public static var defaultReceiptURL: URL {
        AllnighterSupportRoot.config.appendingPathComponent("opencode_ollama_setup.json")
    }

    public static func isRealDefaultConfig(_ url: URL) -> Bool {
        url.standardizedFileURL.path == defaultConfigURL.standardizedFileURL.path
    }

    /// Production CLI path. Tests must pass `--config` (and never the real default).
    public static func resolveConfigURL(
        override: URL?,
        isTestHost: Bool
    ) throws -> URL {
        if let override {
            if isTestHost, isRealDefaultConfig(override) {
                throw Error.testHostRefusedRealConfig(override.path)
            }
            return override
        }
        if isTestHost {
            throw Error.testHostRefusedRealConfig(defaultConfigURL.path)
        }
        return defaultConfigURL
    }

    public static func apply(
        configURL: URL,
        receiptURL: URL,
        now: Date,
        dryRun: Bool,
        fileManager: FileManager = .default
    ) throws -> Report {
        let original = try readOptionalJSON(at: configURL, fileManager: fileManager)
        var root = original.root
        let merge = try OpenCodeOllamaProviderMerge.merge(into: &root)
        let inspection = OpenCodeOllamaProviderMerge.inspect(root)
        let encoded = try OpenCodeOllamaProviderMerge.encodeRoot(root)

        if dryRun || !merge.didChange {
            return report(
                action: dryRun ? "dry-run" : "setup",
                configURL: configURL,
                backupPath: nil,
                wrote: false,
                merge: merge,
                inspection: inspection,
                message: dryRun
                    ? "dry-run: no files written"
                    : (inspection.wired
                        ? "already wired — opencode.json not rewritten"
                        : "nothing to write")
            )
        }

        var backupPath: String?
        if original.existed {
            let backupURL = backupURL(for: configURL, now: now)
            do {
                try fileManager.copyItem(at: configURL, to: backupURL)
            } catch {
                throw Error.io("could not backup \(configURL.path): \(error.localizedDescription)")
            }
            backupPath = backupURL.path
        }

        do {
            try fileManager.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoded.write(to: configURL, options: [.atomic])
        } catch {
            throw Error.io("could not write \(configURL.path): \(error.localizedDescription)")
        }

        let receipt = Receipt(
            configPath: configURL.standardizedFileURL.path,
            backupPath: backupPath,
            addedProvider: merge.addedProvider,
            filledBaseURL: merge.filledBaseURL,
            addedEnabledProvider: merge.addedEnabledProvider,
            appliedAt: iso8601(now)
        )
        try writeReceipt(receipt, to: receiptURL, fileManager: fileManager)

        return report(
            action: "setup",
            configURL: configURL,
            backupPath: backupPath,
            wrote: true,
            merge: merge,
            inspection: inspection,
            message: "merged ollama provider at \(OpenCodeOllamaProviderMerge.defaultBaseURL); undo with \(undoCommand)"
        )
    }

    public static func undo(
        configURL: URL,
        receiptURL: URL,
        now: Date,
        fileManager: FileManager = .default
    ) throws -> Report {
        guard let receipt = try loadReceipt(at: receiptURL) else {
            throw Error.missingReceipt
        }
        let configPath = configURL.standardizedFileURL.path
        if receipt.configPath != configPath {
            throw Error.receiptMismatch("receipt is for \(receipt.configPath)")
        }

        let original = try readOptionalJSON(at: configURL, fileManager: fileManager)
        var root = original.root

        if receipt.addedProvider {
            if var provider = root["provider"] as? [String: Any] {
                provider.removeValue(forKey: OpenCodeOllamaProviderMerge.providerId)
                root["provider"] = provider
            }
        } else if receipt.filledBaseURL {
            stripFilledBaseURL(from: &root)
        }
        if receipt.addedEnabledProvider, var list = root["enabled_providers"] as? [Any] {
            list.removeAll { ($0 as? String) == OpenCodeOllamaProviderMerge.providerId }
            root["enabled_providers"] = list
        }

        var backupPath: String?
        if original.existed {
            let backupURL = backupURL(for: configURL, now: now, suffix: "undo")
            do {
                try fileManager.copyItem(at: configURL, to: backupURL)
            } catch {
                throw Error.io("could not backup \(configURL.path) before undo: \(error.localizedDescription)")
            }
            backupPath = backupURL.path
        }

        let encoded = try OpenCodeOllamaProviderMerge.encodeRoot(root)
        do {
            try encoded.write(to: configURL, options: [.atomic])
        } catch {
            throw Error.io("could not write \(configURL.path): \(error.localizedDescription)")
        }
        try? fileManager.removeItem(at: receiptURL)

        let inspection = OpenCodeOllamaProviderMerge.inspect(root)
        return report(
            action: "undo",
            configURL: configURL,
            backupPath: backupPath,
            wrote: true,
            merge: .init(addedProvider: false, filledBaseURL: false, addedEnabledProvider: false),
            inspection: inspection,
            message: "removed Allnighter's ollama wiring; pre-undo copy at \(backupPath ?? "none")"
        )
    }

    public static func status(
        configURL: URL,
        fileManager: FileManager = .default
    ) throws -> Report {
        let original = try readOptionalJSON(at: configURL, fileManager: fileManager)
        let inspection = OpenCodeOllamaProviderMerge.inspect(original.root)
        return report(
            action: "status",
            configURL: configURL,
            backupPath: nil,
            wrote: false,
            merge: .init(
                addedProvider: false,
                filledBaseURL: false,
                addedEnabledProvider: false
            ),
            inspection: inspection,
            message: original.existed
                ? (inspection.wired ? "OpenCode is wired for local Ollama" : "OpenCode is not fully wired for local Ollama")
                : "no opencode.json at \(configURL.path)"
        )
    }

    // MARK: - Internals

    private struct Loaded {
        var existed: Bool
        var root: [String: Any]
    }

    private static func readOptionalJSON(at url: URL, fileManager: FileManager) throws -> Loaded {
        guard fileManager.fileExists(atPath: url.path) else {
            return Loaded(existed: false, root: [:])
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Error.io("could not read \(url.path): \(error.localizedDescription)")
        }
        do {
            return Loaded(existed: true, root: try OpenCodeOllamaProviderMerge.parseRoot(data))
        } catch let error as OpenCodeOllamaProviderMerge.Error {
            throw Error.merge(error)
        } catch {
            throw Error.invalidJSON(error.localizedDescription)
        }
    }

    private static func backupURL(for configURL: URL, now: Date, suffix: String? = nil) -> URL {
        let stamp = timestamp(now)
        let extra = suffix.map { "-\($0)" } ?? ""
        let name = "\(configURL.lastPathComponent).\(backupInfix)-\(stamp)\(extra)"
        return configURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    private static func timestamp(_ now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: now)
    }

    private static func iso8601(_ now: Date) -> String {
        ISO8601DateFormatter().string(from: now)
    }

    private static func writeReceipt(
        _ receipt: Receipt,
        to url: URL,
        fileManager: FileManager
    ) throws {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try CoreJSON.encode(receipt)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw Error.io("could not write setup receipt \(url.path): \(error.localizedDescription)")
        }
    }

    private static func loadReceipt(at url: URL) throws -> Receipt? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Error.io("could not read setup receipt \(url.path): \(error.localizedDescription)")
        }
        do {
            return try CoreJSON.decode(Receipt.self, from: data)
        } catch {
            throw Error.io("setup receipt is unreadable: \(error.localizedDescription)")
        }
    }

    private static func stripFilledBaseURL(from root: inout [String: Any]) {
        guard var provider = root["provider"] as? [String: Any],
              var ollama = provider[OpenCodeOllamaProviderMerge.providerId] as? [String: Any],
              var options = ollama["options"] as? [String: Any]
        else { return }
        if (options["baseURL"] as? String) == OpenCodeOllamaProviderMerge.defaultBaseURL {
            options.removeValue(forKey: "baseURL")
            if options.isEmpty {
                ollama.removeValue(forKey: "options")
            } else {
                ollama["options"] = options
            }
            provider[OpenCodeOllamaProviderMerge.providerId] = ollama
            root["provider"] = provider
        }
    }

    private static func report(
        action: String,
        configURL: URL,
        backupPath: String?,
        wrote: Bool,
        merge: OpenCodeOllamaProviderMerge.Result,
        inspection: OpenCodeOllamaProviderMerge.Inspection,
        message: String
    ) -> Report {
        Report(
            action: action,
            configPath: configURL.path,
            backupPath: backupPath,
            wrote: wrote,
            addedProvider: merge.addedProvider,
            filledBaseURL: merge.filledBaseURL,
            addedEnabledProvider: merge.addedEnabledProvider,
            alreadyWired: !merge.didChange && inspection.wired,
            wired: inspection.wired,
            enabledProviders: inspection.enabledProviders,
            ollamaBaseURL: inspection.ollamaBaseURL,
            undoCommand: undoCommand,
            message: message
        )
    }
}
