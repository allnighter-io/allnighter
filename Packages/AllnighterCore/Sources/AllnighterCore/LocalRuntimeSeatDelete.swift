import Foundation

/// Delete a seated local row and keep `opencode.json` honest.
///
/// Inverse of S02b mint, matching `OpenCodeOllamaSetup.undo`: unregister only
/// tags this seat's enable actually added (`addedOpenCodeModelIds`). Never
/// unregister a pre-existing tag, a setup-receipt-owned tag, or anything for a
/// Claude-body seat. Tests must pass `opencodeConfigURL` — production resolves
/// the real path; XCTest refuses it.
public enum LocalRuntimeSeatDelete {
    public struct Outcome: Equatable, Sendable {
        public var disclosures: [String]
        public var unregisteredTags: [String]

        public init(disclosures: [String] = [], unregisteredTags: [String] = []) {
            self.disclosures = disclosures
            self.unregisteredTags = unregisteredTags
        }
    }

    public static func delete(
        id: ModelID,
        opencodeConfigURL: URL? = nil,
        setupReceiptURL: URL? = nil,
        fileManager: FileManager = .default,
        isTestHost: Bool = AllnighterSupportRoot.isRunningUnderTestHost
    ) throws -> Outcome {
        guard let existing = ModelCatalog.get(id) else {
            throw ModelCatalogError.notFound(id)
        }
        try ModelCatalog.deleteCustom(id)
        guard existing.driverId == "opencode" else { return Outcome() }
        let owned = existing.addedOpenCodeModelIds ?? []
        guard !owned.isEmpty else { return Outcome() }
        let receiptOwned = Set(OpenCodeOllamaSetup.ownedAddedModelIds(receiptURL: setupReceiptURL))
        var unregistered: [String] = []
        var disclosures: [String] = []
        for tag in owned {
            if remainingOpenCodeSeatNeeds(tag) { continue }
            if receiptOwned.contains(tag) { continue }
            do {
                let removed = try unregister(
                    tag: tag,
                    configURLOverride: opencodeConfigURL,
                    fileManager: fileManager,
                    isTestHost: isTestHost
                )
                guard removed else { continue }
                unregistered.append(tag)
                disclosures.append("Unregistered from opencode.json: \(tag).")
            } catch {
                disclosures.append(
                    "Could not unregister \(tag) from opencode.json: \(describe(error))"
                )
            }
        }
        return Outcome(disclosures: disclosures, unregisteredTags: unregistered)
    }

    // MARK: - OpenCode config

    private static func describe(_ error: Error) -> String {
        if let setup = error as? OpenCodeOllamaSetup.Error { return setup.description }
        if case .invalid(let message) = error as? ModelCatalogError { return message }
        return error.localizedDescription
    }

    private static func remainingOpenCodeSeatNeeds(_ tag: String) -> Bool {
        ModelCatalog.list().contains { def in
            def.driverId == "opencode"
                && OpenCodeLocalSeatReadiness.ollamaTag(from: def.modelLabel) == tag
        }
    }

    private static func unregister(
        tag: String,
        configURLOverride: URL?,
        fileManager: FileManager,
        isTestHost: Bool
    ) throws -> Bool {
        let configURL = try OpenCodeOllamaSetup.resolveConfigURL(
            override: configURLOverride,
            isTestHost: isTestHost
        )
        guard fileManager.fileExists(atPath: configURL.path) else { return false }
        var root = try readOpenCodeRoot(at: configURL, fileManager: fileManager)
        let before = OpenCodeOllamaProviderMerge.inspect(root).ollamaModelIds ?? []
        guard before.contains(tag) else { return false }
        OpenCodeOllamaProviderMerge.removeAddedModels(
            from: &root,
            ids: [tag],
            dropEmptyMap: false
        )
        let after = OpenCodeOllamaProviderMerge.inspect(root).ollamaModelIds ?? []
        guard !after.contains(tag) else { return false }
        let encoded = try OpenCodeOllamaProviderMerge.encodeRoot(root)
        do {
            try encoded.write(to: configURL, options: [.atomic])
        } catch {
            throw ModelCatalogError.invalid(
                "could not write \(configURL.path): \(error.localizedDescription)"
            )
        }
        return true
    }

    private static func readOpenCodeRoot(
        at url: URL,
        fileManager: FileManager
    ) throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ModelCatalogError.invalid(
                "could not read \(url.path): \(error.localizedDescription)"
            )
        }
        do {
            return try OpenCodeOllamaProviderMerge.parseRoot(data)
        } catch let error as OpenCodeOllamaProviderMerge.Error {
            throw ModelCatalogError.invalid(error.description)
        } catch {
            throw ModelCatalogError.invalid(
                "opencode.json is not valid JSON (\(error.localizedDescription)) — refusing to clobber it"
            )
        }
    }
}
