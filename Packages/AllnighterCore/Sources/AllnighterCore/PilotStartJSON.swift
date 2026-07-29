import Foundation

/// `pilot start --json` envelope — relay state plus the next command and scaffold path
/// (`Pilot_DX.md §DX4`).
public struct PilotStartJSON: Codable, Equatable, Sendable {
    public var relay: RelayJSON
    public var nextCommand: String
    public var scaffoldPath: String
    /// The dev seat model id actually used (after alias resolution).
    public var devModelId: String
    /// Present when `--dev-model` was omitted and the last-used seat was recalled.
    public var rememberedDevWorker: Bool?

    public init(
        relay: RelayJSON,
        nextCommand: String,
        scaffoldPath: String,
        devModelId: String,
        rememberedDevWorker: Bool? = nil
    ) {
        self.relay = relay
        self.nextCommand = nextCommand
        self.scaffoldPath = scaffoldPath
        self.devModelId = devModelId
        self.rememberedDevWorker = rememberedDevWorker
    }
}
