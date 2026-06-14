import Foundation

/// Loads bundled JSON fixtures so the app and tests build against identical
/// data before any real CLI is wired.
public enum Fixtures {
    public enum FixtureError: Error, CustomStringConvertible {
        case notFound(String)

        public var description: String {
            switch self {
            case .notFound(let name): return "Fixture not found: \(name)"
            }
        }
    }

    /// Names of the bundled fixtures (without `.json`).
    public enum Name: String, CaseIterable {
        case panelSix = "panel_six"
        case manifestClaude = "manifest_claude"
        case manifestGrok = "manifest_grok"
        case manifestManual = "manifest_manual"
        case runInflight = "run_inflight"
        case runComplete = "run_complete"
        case runPartial = "run_partial"
    }

    public static func data(_ name: Name) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name.rawValue,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw FixtureError.notFound(name.rawValue)
        }
        return try Data(contentsOf: url)
    }

    public static func decode<T: Decodable>(_ type: T.Type, _ name: Name) throws -> T {
        try CoreJSON.decode(type, from: data(name))
    }

    // Convenience typed accessors.
    public static func panel() throws -> [Worker] {
        try decode([Worker].self, .panelSix)
    }

    public static func run(_ name: Name) throws -> CouncilRun {
        try decode(CouncilRun.self, name)
    }

    public static func manifest(_ name: Name) throws -> DriverManifest {
        try decode(DriverManifest.self, name)
    }
}
