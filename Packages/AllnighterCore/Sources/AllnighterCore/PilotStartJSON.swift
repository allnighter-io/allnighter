import Foundation

/// `pilot start --json` envelope — relay state plus the next command and scaffold path
/// (`Pilot_DX.md §DX4`).
///
/// **Programmatic consumers:** use `scaffoldPath` (raw path) and/or `nextCommandArgv`
/// (token array with unquoted path). Do **not** parse `nextCommand` — that string is
/// shell-quoted for human paste under paths with spaces (`Application Support/…`).
public struct PilotStartJSON: Codable, Equatable, Sendable {
    public var relay: RelayJSON
    /// Shell-ready one-liner for human paste (`--handover-file '…'` single-quoted).
    public var nextCommand: String
    /// Absolute scaffold path — raw, never shell-quoted. Prefer this over parsing `nextCommand`.
    public var scaffoldPath: String
    /// Argv tokens after `alln` for programmatic spawn (path unquoted). Additive (DX polish).
    public var nextCommandArgv: [String]
    /// The dev seat model id actually used (after alias resolution).
    public var devModelId: String
    /// Present when `--dev-model` was omitted and the last-used seat was recalled.
    public var rememberedDevWorker: Bool?

    public init(
        relay: RelayJSON,
        nextCommand: String,
        scaffoldPath: String,
        nextCommandArgv: [String]? = nil,
        devModelId: String,
        rememberedDevWorker: Bool? = nil
    ) {
        self.relay = relay
        self.nextCommand = nextCommand
        self.scaffoldPath = scaffoldPath
        self.nextCommandArgv = nextCommandArgv
            ?? Self.defaultHandoffArgv(relayId: relay.relayId, scaffoldPath: scaffoldPath)
        self.devModelId = devModelId
        self.rememberedDevWorker = rememberedDevWorker
    }

    /// Token form of the first handoff — path is a bare string, not shell-quoted.
    public static func defaultHandoffArgv(relayId: String, scaffoldPath: String) -> [String] {
        [
            "pair", "pilot", "handoff",
            "--relay", relayId,
            "--verdict", "continue",
            "--handover-file", scaffoldPath,
        ]
    }
}
