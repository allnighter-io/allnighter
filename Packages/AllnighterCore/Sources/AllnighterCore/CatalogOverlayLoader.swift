import Foundation
import AgentOSCLI

/// Policy-only overlay merged onto the AgentOS catalog (`defaultOn`, `hidden`,
/// `caliber`, `menuHint`). Wire labels and effort live in AgentOS `catalog.json`.
public struct CatalogOverlay: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var models: [String: CatalogOverlayModel]

    public init(schemaVersion: Int = 1, models: [String: CatalogOverlayModel] = [:]) {
        self.schemaVersion = schemaVersion
        self.models = models
    }
}

public struct CatalogOverlayModel: Codable, Sendable, Equatable {
    public var defaultOn: Bool?
    public var hidden: Bool?
    /// Bench default reasoning effort when the run does not pass an explicit `--effort`.
    public var defaultEffort: String?
    public var caliber: ModelCapabilities?
    public var menuHint: CatalogMenuHint?

    public init(
        defaultOn: Bool? = nil,
        hidden: Bool? = nil,
        defaultEffort: String? = nil,
        caliber: ModelCapabilities? = nil,
        menuHint: CatalogMenuHint? = nil
    ) {
        self.defaultOn = defaultOn
        self.hidden = hidden
        self.defaultEffort = defaultEffort
        self.caliber = caliber
        self.menuHint = menuHint
    }
}

public struct CatalogMenuHint: Codable, Sendable, Equatable {
    public var useWhen: String
    public var dontUseWhen: String

    public init(useWhen: String, dontUseWhen: String) {
        self.useWhen = useWhen
        self.dontUseWhen = dontUseWhen
    }
}

public enum CatalogOverlayLoaderError: Error, Equatable, CustomStringConvertible {
    case missingBundledResource
    case unreadableResource(String)
    case invalidJSON(String)
    case validationFailed([String])
    case unknownSchemaVersion(Int)

    public var description: String {
        switch self {
        case .missingBundledResource:
            return "bundled catalog overlay resource is missing"
        case let .unreadableResource(message):
            return "bundled catalog overlay is unreadable: \(message)"
        case let .invalidJSON(message):
            return "catalog overlay JSON is invalid: \(message)"
        case let .validationFailed(problems):
            return "catalog overlay validation failed: \(problems.joined(separator: "; "))"
        case let .unknownSchemaVersion(version):
            return "unsupported catalog overlay schemaVersion \(version)"
        }
    }
}

public enum CatalogOverlayLoader {
    private static let supportedSchemaVersion = 1

    public static func bundled() throws -> CatalogOverlay {
        try bundled(bundle: overlayBundle())
    }

    public static func bundled(bundle: Bundle) throws -> CatalogOverlay {
        let candidates = [
            bundle.url(forResource: "catalog_overlay", withExtension: "json", subdirectory: "Catalog"),
            bundle.url(forResource: "catalog_overlay", withExtension: "json"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            throw CatalogOverlayLoaderError.missingBundledResource
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CatalogOverlayLoaderError.unreadableResource(error.localizedDescription)
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> CatalogOverlay {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CatalogOverlayLoaderError.invalidJSON(error.localizedDescription)
        }
        guard let root = object as? [String: Any] else {
            throw CatalogOverlayLoaderError.invalidJSON("root must be an object")
        }

        var problems: [String] = []
        validateKnownKeys(
            root,
            allowed: ["schemaVersion", "models"],
            path: "$",
            problems: &problems
        )
        if !problems.isEmpty {
            throw CatalogOverlayLoaderError.validationFailed(problems)
        }

        let overlay: CatalogOverlay
        do {
            overlay = try CoreJSON.decode(CatalogOverlay.self, from: data)
        } catch {
            throw CatalogOverlayLoaderError.invalidJSON(error.localizedDescription)
        }
        try validate(overlay, rawRoot: root)
        return overlay
    }

    private static func validate(_ overlay: CatalogOverlay, rawRoot: [String: Any]) throws {
        var problems: [String] = []
        if overlay.schemaVersion != supportedSchemaVersion {
            throw CatalogOverlayLoaderError.unknownSchemaVersion(overlay.schemaVersion)
        }

        if let rawModels = rawRoot["models"] as? [String: Any] {
            for (modelId, value) in rawModels {
                guard let row = value as? [String: Any] else { continue }
                validateKnownKeys(
                    row,
                    allowed: ["defaultOn", "hidden", "defaultEffort", "caliber", "menuHint"],
                    path: "$.models.\(modelId)",
                    problems: &problems
                )
                if let raw = row["defaultEffort"] as? String,
                   EffortLevel(rawValue: raw) == nil {
                    problems.append("$.models.\(modelId).defaultEffort must be low, med, or high")
                }
                if row["hidden"] as? Bool == true, row["defaultOn"] as? Bool == true {
                    problems.append("$.models.\(modelId): hidden and defaultOn cannot both be true")
                }
                if let caliber = row["caliber"] as? [String: Any] {
                    validateKnownKeys(
                        caliber,
                        allowed: ["laneTags", "capabilityTags", "strengthRank"],
                        path: "$.models.\(modelId).caliber",
                        problems: &problems
                    )
                    if let rank = caliber["strengthRank"] as? Double, rank != Double(Int(rank)) {
                        problems.append("$.models.\(modelId).caliber.strengthRank must be integral")
                    }
                    if let rank = caliber["strengthRank"] as? Int, !(0...100).contains(rank) {
                        problems.append("$.models.\(modelId).caliber.strengthRank out of range")
                    }
                }
                if let hint = row["menuHint"] as? [String: Any] {
                    validateKnownKeys(
                        hint,
                        allowed: ["useWhen", "dontUseWhen"],
                        path: "$.models.\(modelId).menuHint",
                        problems: &problems
                    )
                }
            }
        }

        if !problems.isEmpty {
            throw CatalogOverlayLoaderError.validationFailed(problems)
        }
    }

    private static func validateKnownKeys(
        _ object: [String: Any],
        allowed: Set<String>,
        path: String,
        problems: inout [String]
    ) {
        for key in object.keys where !allowed.contains(key) {
            problems.append("\(path): unknown field '\(key)'")
        }
    }

    private static func overlayBundle() -> Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: BundleToken.self)
        #endif
    }
}

private final class BundleToken {}
