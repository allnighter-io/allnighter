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
        case modelsSix = "models_six"
        case manifestClaude = "manifest_claude"
        case manifestGrok = "manifest_grok"
        case manifestManual = "manifest_manual"
        case runInflight = "run_inflight"
        case runComplete = "run_complete"
        case runPartial = "run_partial"
        case synthesisPresetDefault = "synthesis_preset_default"
        case teamPresetDefault = "team_preset_default"
        case threadChat = "thread_chat"
        case threadImported = "thread_imported"
        case threadContextPacket = "thread_context_packet"
        case teamRunJSON = "team_run"
        case doctorResult = "doctor_result"
        case errorEnvelope = "error_envelope"
        case pendingItemJSON = "pending_item"
        case pendingItemCoolingJSON = "pending_item_cooling"
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
    public static func models() throws -> [Model] {
        try decode([Model].self, .modelsSix)
    }

    public static func run(_ name: Name) throws -> TeamRun {
        try decode(TeamRun.self, name)
    }

    public static func manifest(_ name: Name) throws -> DriverManifest {
        try decode(DriverManifest.self, name)
    }

    public static func synthesisPreset() throws -> SynthesisInstructionPreset {
        try decode(SynthesisInstructionPreset.self, .synthesisPresetDefault)
    }

    public static func panelPreset() throws -> PanelPreset {
        try decode(PanelPreset.self, .teamPresetDefault)
    }

    public static func thread(_ name: Name = .threadChat) throws -> WorkThread {
        try decode(WorkThread.self, name)
    }

    public static func teamRunJSON() throws -> Data {
        try data(.teamRunJSON)
    }

    public static func contextPacket() throws -> ThreadContextPacket {
        try decode(ThreadContextPacket.self, .threadContextPacket)
    }

    public static func pendingItemJSON() throws -> PendingItemJSON {
        try decode(PendingItemJSON.self, .pendingItemJSON)
    }

    public static func pendingItemCoolingJSON() throws -> PendingItemJSON {
        try decode(PendingItemJSON.self, .pendingItemCoolingJSON)
    }
}
