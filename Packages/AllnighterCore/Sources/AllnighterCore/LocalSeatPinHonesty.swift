import Foundation

/// One honesty standard for preferred-pin substitution, local or paid.
/// Cross-boundary automatic substitution is refused (Project_Laws
/// §Local and cloud seats, 2026-08-15).
public enum LocalSeatPinHonesty {
    public static func isLocalSeat(_ model: Model) -> Bool {
        ModelCatalog.isLocalAutomaticSubstitute(
            driverId: model.driverId, modelLabel: model.modelLabel)
    }

    public static func sameSide(_ a: Model, _ b: Model) -> Bool {
        isLocalSeat(a) == isLocalSeat(b)
    }

    public static func filterSameSide(as pin: Model, in models: [Model]) -> [Model] {
        models.filter { sameSide(pin, $0) }
    }

    /// Human reason clause after "which is unavailable because …".
    /// Nil snapshot is unobserved, never a guessed Available.
    public static func sensorReading(
        modelLabel: String,
        snapshot: OllamaLocalRuntimeObserver.Snapshot?
    ) -> String {
        guard let snapshot else { return "Allnighter has not checked Ollama yet" }
        if snapshot.ollamaVersion == nil { return "Ollama is not reachable" }
        if !OpenCodeLocalSeatReadiness.tagIsPresentLocally(
            modelLabel: modelLabel, snapshot: snapshot
        ) {
            return "that model is not on this Mac"
        }
        return "it is not ready"
    }

    public static func substitutionWarning(
        skillName: String,
        pinId: String,
        pinDisplayName: String,
        unavailableBecause: String?,
        substituteDisplayName: String
    ) -> String {
        var sentence = "\(skillName) asked for \(pinDisplayName) (\(pinId)), which is unavailable"
        if let unavailableBecause, !unavailableBecause.isEmpty {
            sentence += " because \(unavailableBecause)"
        }
        sentence += ". Allnighter is using \(substituteDisplayName) instead."
        return sentence
    }

    public static func unavailableRefusal(pinId: String, pinDisplayName: String) -> String {
        "\(pinDisplayName) is unavailable. Run alln menu --json to pick another model."
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
