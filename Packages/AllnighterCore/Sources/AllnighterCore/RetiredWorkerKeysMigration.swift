import Foundation

/// One-time on-disk migration for retired worker keys under support root (WTA-S03a).
///
/// JSON-path-aware rewrites (S00 D1a — `teamRun.workerId` is a model pin, not a seat):
/// - `teamRun.workerId` → `teamRun.modelId`
/// - `workerAnswers` → `answers`; answer-row `workerId` → `agentId`
/// - `producedByWorkerId` → `producedByAgentId`
/// - `devWorkerId` → `devModelId`
/// - `pmWorkerId` → `pmModelId`
/// - TeamRunJSON root `workers` → `agents` (when `schemaVersion` + `teamRun` present)
///
/// Idempotent (safe to run multiple times). Skips files with no retired keys.
public enum RetiredWorkerKeysMigration {
    public struct MigrationResult: Equatable, Sendable {
        public var scannedFileCount: Int
        public var migratedFileCount: Int
        public var totalReplacementsCount: Int

        public init(scannedFileCount: Int, migratedFileCount: Int, totalReplacementsCount: Int) {
            self.scannedFileCount = scannedFileCount
            self.migratedFileCount = migratedFileCount
            self.totalReplacementsCount = totalReplacementsCount
        }
    }

    private static let retiredKeyMarkers = [
        "producedByWorkerId", "devWorkerId", "pmWorkerId", "workerAnswers", "\"workerId\""
    ]

    /// Run the on-disk migration against the specified support root URL.
    @discardableResult
    public static func migrate(supportRoot: URL) throws -> MigrationResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: supportRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return MigrationResult(scannedFileCount: 0, migratedFileCount: 0, totalReplacementsCount: 0)
        }

        let enumerator = fileManager.enumerator(
            at: supportRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var scannedCount = 0
        var migratedCount = 0
        var totalReplacements = 0

        while let fileURL = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }

            let ext = fileURL.pathExtension.lowercased()
            guard ext == "json" || ext == "ndjson" || ext == "log" || ext == "txt" || ext.isEmpty else {
                continue
            }

            scannedCount += 1

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            guard retiredKeyMarkers.contains(where: { content.contains($0) }) else {
                continue
            }

            let migrated: (content: String, replacements: Int)?
            switch ext {
            case "ndjson":
                migrated = migrateNDJSONContent(content)
            default:
                migrated = migrateJSONContent(content)
            }

            guard let migrated, migrated.replacements > 0 else {
                continue
            }

            try migrated.content.write(to: fileURL, atomically: true, encoding: .utf8)
            migratedCount += 1
            totalReplacements += migrated.replacements
        }

        return MigrationResult(
            scannedFileCount: scannedCount,
            migratedFileCount: migratedCount,
            totalReplacementsCount: totalReplacements
        )
    }

    // MARK: - JSON migration (path-aware)

    static func migrateKey(
        _ key: String,
        parentKey: String?,
        teamRunJSONRoot: Bool = false
    ) -> (newKey: String, renamed: Bool) {
        switch key {
        case "producedByWorkerId":
            return ("producedByAgentId", true)
        case "devWorkerId":
            return ("devModelId", true)
        case "pmWorkerId":
            return ("pmModelId", true)
        case "workerAnswers":
            return ("answers", true)
        case "workers":
            if teamRunJSONRoot {
                return ("agents", true)
            }
            return (key, false)
        case "writerWorkerId":
            return ("writerAgentId", true)
        case "planWriterWorkerId":
            return ("planWriterAgentId", true)
        case "workerId":
            if parentKey == "teamRun" {
                return ("modelId", true)
            }
            return ("agentId", true)
        default:
            return (key, false)
        }
    }

    static func migrateJSONObject(_ object: [String: Any], parentKey: String?) -> ([String: Any], Int) {
        let teamRunJSONRoot = parentKey == nil
            && object["teamRun"] != nil
            && object["schemaVersion"] != nil
        var replacements = 0
        var result: [String: Any] = [:]
        result.reserveCapacity(object.count)

        for (key, value) in object {
            let (newKey, renamed) = migrateKey(
                key,
                parentKey: parentKey,
                teamRunJSONRoot: teamRunJSONRoot
            )
            if renamed { replacements += 1 }
            let (newValue, childReplacements) = migrateJSONValue(value, parentKey: newKey)
            replacements += childReplacements
            result[newKey] = newValue
        }
        return (result, replacements)
    }

    static func migrateJSONValue(_ value: Any, parentKey: String?) -> (Any, Int) {
        switch value {
        case let object as [String: Any]:
            return migrateJSONObject(object, parentKey: parentKey)
        case let array as [Any]:
            var replacements = 0
            let migrated = array.map { item -> Any in
                let (newItem, count) = migrateJSONValue(item, parentKey: parentKey)
                replacements += count
                return newItem
            }
            return (migrated, replacements)
        default:
            return (value, 0)
        }
    }

    static func serializeJSONObject(_ object: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw MigrationError.invalidJSONObject
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw MigrationError.encodingFailed
        }
        return text + "\n"
    }

    static func migrateJSONContent(_ content: String) -> (content: String, replacements: Int)? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let (migrated, replacements) = migrateJSONValue(root, parentKey: nil)
        guard replacements > 0 else { return nil }
        guard let text = try? serializeJSONObject(migrated) else { return nil }
        return (text, replacements)
    }

    static func migrateNDJSONContent(_ content: String) -> (content: String, replacements: Int)? {
        var totalReplacements = 0
        var migratedLines: [String] = []
        migratedLines.reserveCapacity(content.components(separatedBy: "\n").count)

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                migratedLines.append(line)
                continue
            }
            guard let data = trimmed.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) else {
                migratedLines.append(line)
                continue
            }
            let (migrated, replacements) = migrateJSONValue(root, parentKey: nil)
            if replacements > 0,
               let text = try? serializeJSONObject(migrated).trimmingCharacters(in: .newlines) {
                migratedLines.append(text)
                totalReplacements += replacements
            } else {
                migratedLines.append(line)
            }
        }

        guard totalReplacements > 0 else { return nil }
        return (migratedLines.joined(separator: "\n"), totalReplacements)
    }

    enum MigrationError: Error {
        case invalidJSONObject
        case encodingFailed
    }
}
