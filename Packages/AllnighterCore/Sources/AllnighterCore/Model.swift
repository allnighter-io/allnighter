import Foundation

/// A configured model endpoint: a specific model reached through a specific
/// driver (CLI). Two workers can share one driver and differ only by
/// `modelLabel` — e.g. Opus/Sonnet both use `claude_code`, and Grok Build /
/// Composer 2.5 both use the `grok` driver.
public struct Model: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    /// The model identifier passed to the driver's `{{model}}` token.
    public var modelLabel: String
    /// `DriverManifest.id` this worker is invoked through.
    public var driverId: String
    public var role: ModelRole
    public var enabled: Bool
    /// Per-effort model-label overrides (Antigravity encodes effort in the model
    /// name). nil = constant label; effort, if any, applies as a driver flag.
    public var effortVariants: [EffortLevel: String]?

    public init(
        id: String,
        displayName: String,
        modelLabel: String,
        driverId: String,
        role: ModelRole = .answerer,
        enabled: Bool = true,
        effortVariants: [EffortLevel: String]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.modelLabel = modelLabel
        self.driverId = driverId
        self.role = role
        self.enabled = enabled
        self.effortVariants = effortVariants
    }

    /// Can this worker produce the plan?
    public var canWritePlan: Bool {
        role == .planWriter || role == .both
    }

    /// The exact `{{model}}` label to pass at `effort` — the effort variant if this
    /// model encodes effort in its name, else the constant label.
    public func resolvedLabel(at effort: EffortLevel) -> String {
        effortVariants?[effort] ?? modelLabel
    }
}
