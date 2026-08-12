import Foundation
import AgentOSCLI

/// Catalog latest-resolution recorded at run acceptance.
///
/// `requestedId` is what the caller said (`model_grok`). `pinId` + `modelLabel`
/// are the derived concrete seat (`model_grok_46` / `grok-4.6`). A receipt that
/// stored only the pure name would not be replayable after the next generation
/// ships. Pins and vendor aliases record identity (`pinId == requestedId`).
public struct ModelPinFact: Codable, Sendable, Equatable {
    public var requestedId: String
    public var pinId: String
    public var modelLabel: String

    public init(requestedId: String, pinId: String, modelLabel: String) {
        self.requestedId = requestedId
        self.pinId = pinId
        self.modelLabel = modelLabel
    }

    public static func facts(requestedIds: [String]?, models: [Model]) -> [ModelPinFact]? {
        guard let requestedIds, !requestedIds.isEmpty else { return nil }
        return requestedIds.map { id in
            let model = models.first { $0.id == id }
            return ModelPinFact(
                requestedId: id,
                pinId: model?.replayModelId ?? id,
                modelLabel: model?.modelLabel ?? ""
            )
        }
    }
}
