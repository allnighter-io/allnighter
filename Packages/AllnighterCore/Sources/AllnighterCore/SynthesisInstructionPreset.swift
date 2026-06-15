import Foundation

/// A named, editable instruction template for the draft master-plan synthesis.
/// The built-in default is `default_master_plan_v1`; users may add custom
/// presets (Phase 05). A `TeamPreset` references one by id via
/// `draftSynthesisInstructionPresetId`, and a completed run records the id (or
/// the literal custom text) it actually used in `Synthesis.instructions` — so
/// the persisted truth is honest, never always-`default_master_plan_v1`.
public struct SynthesisInstructionPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    /// The instruction text handed to the plan writer (the prompt prefix).
    public var template: String
    /// True for app-bundled presets the user did not author.
    public var builtIn: Bool

    public init(
        id: String,
        displayName: String,
        template: String,
        builtIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.template = template
        self.builtIn = builtIn
    }
}
