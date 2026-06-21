import Foundation

// MARK: - Envelope

public enum CatalogKind: String, Codable, Sendable {
    case team
    case skill
    case model
}

public struct CatalogEnvelope<T: Codable & Sendable>: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: CatalogKind
    public var definition: T

    public init(schemaVersion: Int = 1, kind: CatalogKind, definition: T) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.definition = definition
    }
}

// MARK: - Errors

public enum CatalogError: Error, Equatable, Sendable {
    case teamNotFound
    case skillNotFound
    case modelNotFound
    case builtInImmutable
    case idCollision
    case idInvalid
    case teamInvalid(String)
    case skillInvalid(String)
    case skillLaneMismatch(skillId: SkillID, teamId: TeamID)
    case skillInUse(referencingTeamIDs: [TeamID])
    case teamDefaultInvalid(String)
    /// Restore was requested for a team id that has no shipped seed to restore to
    /// (an ordinary custom team, not a built-in).
    case restoreUnsupported
}

// MARK: - ID rules

public enum CatalogIDValidator {
  private static let pattern = #"^[a-z][a-z0-9_]{2,63}$"#

    public static func isValid(_ id: String) -> Bool {
        id.range(of: pattern, options: .regularExpression) != nil
    }

    public static func isValidCustom(_ id: String, lane: WorkLane) -> Bool {
        id.hasPrefix("custom_\(lane.rawValue)_") && isValid(id)
    }
}

public enum CatalogIDGenerator {
    public static func customID(lane: WorkLane, displayName: String, suffix: String = "") -> SkillID {
        let slug = slugify(displayName)
        let base = "custom_\(lane.rawValue)_\(slug)\(suffix.isEmpty ? "" : "_\(suffix)")"
        return String(base.prefix(64))
    }

    private static func slugify(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        for ch in lowered.unicodeScalars {
            if ch.isASCII && (ch.properties.isAlphabetic || ch.properties.numericType == .decimal) {
                out.append(Character(ch))
            } else if ch == " " || ch == "-" {
                out.append("_")
            }
        }
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if out.isEmpty { out = "item" }
        if let first = out.first, !first.isLetter { out = "x_\(out)" }
        return String(out.prefix(48))
    }
}

// MARK: - Roots (overridable in tests)

public enum CatalogRoots {
    nonisolated(unsafe) private static var teamsOverride: URL?
    nonisolated(unsafe) private static var skillsOverride: URL?
    nonisolated(unsafe) private static var modelsOverride: URL?

    public static var teams: URL {
        teamsOverride ?? defaultSupport.appendingPathComponent("Catalogs/teams", isDirectory: true)
    }

    public static var skills: URL {
        skillsOverride ?? defaultSupport.appendingPathComponent("Catalogs/skills", isDirectory: true)
    }

    public static var models: URL {
        modelsOverride ?? defaultSupport.appendingPathComponent("Catalogs/models", isDirectory: true)
    }

    private static var defaultSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Allnighter", isDirectory: true)
    }

    public static func overrideForTesting(teams: URL, skills: URL, models: URL? = nil) {
        teamsOverride = teams
        skillsOverride = skills
        modelsOverride = models
    }

    public static func resetTestingOverrides() {
        teamsOverride = nil
        skillsOverride = nil
        modelsOverride = nil
    }
}

// MARK: - File IO (private plumbing)

enum CatalogFileIO {
    static func loadAll<T: Codable & Sendable>(kind: CatalogKind, root: URL, as type: T.Type) -> [T] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> T? in
                guard let data = try? Data(contentsOf: url),
                      let envelope = try? CoreJSON.decode(CatalogEnvelope<T>.self, from: data),
                      envelope.kind == kind else { return nil }
                return envelope.definition
            }
    }

    static func loadOne<T: Codable & Sendable>(id: String, kind: CatalogKind, root: URL, as type: T.Type) -> T? {
        let url = root.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url),
              let envelope = try? CoreJSON.decode(CatalogEnvelope<T>.self, from: data),
              envelope.kind == kind else { return nil }
        return envelope.definition
    }

    @discardableResult
    static func save<T: Codable & Sendable>(_ definition: T, id: String, kind: CatalogKind, root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("\(id).json")
        let envelope = CatalogEnvelope(kind: kind, definition: definition)
        try CoreJSON.encode(envelope).write(to: url, options: .atomic)
        return url
    }

    static func delete(id: String, root: URL) throws {
        let url = root.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
