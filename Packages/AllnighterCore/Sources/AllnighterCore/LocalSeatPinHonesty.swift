import Foundation

/// LR-S04b — local-pin substitution must name the pin, the Ollama sensor
/// reading, and the substitute. Paid-pin fallback wording is unchanged.
public enum LocalSeatPinHonesty {
    public static func isLocalSeat(_ model: Model) -> Bool {
        ModelCatalog.isLocalAutomaticSubstitute(
            driverId: model.driverId, modelLabel: model.modelLabel)
    }

    /// Human sensor line. Nil snapshot is unobserved, never a guessed Available.
    public static func sensorReading(
        modelLabel: String,
        snapshot: OllamaLocalRuntimeObserver.Snapshot?
    ) -> String {
        guard let snapshot else { return "Ollama unobserved" }
        if snapshot.ollamaVersion == nil { return "Ollama not reachable" }
        if !OpenCodeLocalSeatReadiness.tagIsPresentLocally(
            modelLabel: modelLabel, snapshot: snapshot
        ) {
            let tag = OpenCodeLocalSeatReadiness.ollamaTag(from: modelLabel) ?? modelLabel
            return "tag not present locally: \(tag)"
        }
        return "excluded from ready-set"
    }

    public static func substitutionWarning(
        skillName: String,
        pinId: String,
        pinLabel: String,
        sensorReading: String,
        substituteDisplayName: String
    ) -> String {
        "LOCAL PIN SUBSTITUTED: \(skillName) preferred \(pinId) (\(pinLabel)) — sensor: \(sensorReading); substituted paid seat \(substituteDisplayName)."
    }

    public static func lookupPin(
        id: String,
        ready: [Model],
        catalogModels: [Model]
    ) -> Model? {
        if let model = ready.first(where: { $0.id == id }) { return model }
        if let model = catalogModels.first(where: { $0.id == id }) { return model }
        guard let def = ModelCatalog.get(id) else { return nil }
        return Model(
            id: def.id,
            displayName: def.displayName,
            modelLabel: def.modelLabel,
            driverId: def.driverId,
            role: def.role,
            enabled: def.defaultEnabled
        )
    }
}
