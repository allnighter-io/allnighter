import Foundation

/// A configured model endpoint: a specific model reached through a specific
/// driver (CLI). Two workers can share one driver and differ only by
/// `modelLabel` — e.g. Opus/Sonnet both use `claude_code`, and Grok Build /
/// Composer 2.5 both use the `grok` driver.
public struct Worker: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    /// The model identifier passed to the driver's `{{model}}` token.
    public var modelLabel: String
    /// `DriverManifest.id` this worker is invoked through.
    public var driverId: String
    public var role: WorkerRole
    public var enabled: Bool

    public init(
        id: String,
        displayName: String,
        modelLabel: String,
        driverId: String,
        role: WorkerRole = .member,
        enabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.modelLabel = modelLabel
        self.driverId = driverId
        self.role = role
        self.enabled = enabled
    }

    /// Can this worker produce the master plan?
    public var canSynthesize: Bool {
        role == .synthesizer || role == .both
    }
}
