import AllnighterCore

extension AppModel {
    /// Resolves catalog-backed display names for a thread turn's agent header.
    func threadAgentLabel(for turn: ThreadTurn) -> ThreadAgentPresentation.Label {
        let modelId = turn.modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedId = (modelId?.isEmpty == false) ? modelId : nil

        if let normalizedId, let bench = composeBench.first(where: { $0.id == normalizedId }) {
            return ThreadAgentPresentation.make(
                threadId: turn.threadId,
                turnId: turn.id,
                modelId: normalizedId,
                modelDisplayName: bench.name,
                driverId: bench.driverId
            )
        }
        if let normalizedId, let model = models.first(where: { $0.id == normalizedId }) {
            let name = ModelDisplayName.format(
                baseName: model.displayName, modelId: model.id, driverId: model.driverId
            )
            return ThreadAgentPresentation.make(
                threadId: turn.threadId,
                turnId: turn.id,
                modelId: normalizedId,
                modelDisplayName: name,
                driverId: model.driverId
            )
        }
        return ThreadAgentPresentation.make(
            threadId: turn.threadId,
            turnId: turn.id,
            modelId: normalizedId,
            modelDisplayName: nil,
            driverId: nil
        )
    }
}
