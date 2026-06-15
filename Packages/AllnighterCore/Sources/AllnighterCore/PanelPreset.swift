import Foundation

/// A saved, named panel configuration so the daily ritual is one click: which
/// workers answer, which one writes the draft master plan, and which synthesis
/// instruction preset that synthesizer uses. Each field is explicit (no
/// hardcoded "Opus always synthesizes"): the built-in default merely *defaults*
/// the synthesizer to Opus by configuration.
public struct PanelPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    /// Worker ids the prompt is sent to, in display order.
    public var panelWorkerIds: [String]
    /// The worker that writes the draft master plan. Must be in `panelWorkerIds`
    /// and able to synthesize.
    public var draftSynthesizerWorkerId: String
    /// `SynthesisInstructionPreset.id` the synthesizer uses for the draft plan.
    public var draftSynthesisInstructionPresetId: String
    /// True for the app-bundled default the user did not author.
    public var builtIn: Bool

    public init(
        id: String,
        displayName: String,
        panelWorkerIds: [String],
        draftSynthesizerWorkerId: String,
        draftSynthesisInstructionPresetId: String,
        builtIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.panelWorkerIds = panelWorkerIds
        self.draftSynthesizerWorkerId = draftSynthesizerWorkerId
        self.draftSynthesisInstructionPresetId = draftSynthesisInstructionPresetId
        self.builtIn = builtIn
    }

    /// Builds the founder's six-worker default preset from a concrete panel.
    /// The synthesizer defaults to the first worker that can synthesize (Opus in
    /// the bundled panel) unless one is named — by configuration, not a code path.
    public static func builtInDefault(
        id: String = "preset_six_default",
        displayName: String = "Founder's Six",
        panel: [Worker],
        synthesizerWorkerId: String? = nil,
        instructionPresetId: String
    ) -> PanelPreset {
        let synthId = synthesizerWorkerId
            ?? panel.first(where: \.canSynthesize)?.id
            ?? panel.first?.id
            ?? ""
        return PanelPreset(
            id: id,
            displayName: displayName,
            panelWorkerIds: panel.map(\.id),
            draftSynthesizerWorkerId: synthId,
            draftSynthesisInstructionPresetId: instructionPresetId,
            builtIn: true
        )
    }
}
