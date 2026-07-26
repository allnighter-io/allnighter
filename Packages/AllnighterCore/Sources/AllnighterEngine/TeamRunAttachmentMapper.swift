import Foundation
import AllnighterCore

/// Team-run attachment delivery helpers for seat prompts.
public enum TeamRunAttachmentMapper {
    public static func teamRunSeatPrompt(
        basePrompt: String,
        deliveries: [IncludedAttachmentDelivery],
        readsImages: Bool
    ) -> String {
        AttachmentDeliveryRenderer.teamRunSeatPrompt(
            basePrompt: basePrompt,
            deliveries: deliveries,
            readsImages: readsImages
        )
    }

    public static func warnings(
        resolvedWorkers: [(workerId: String, readsImages: Bool)],
        deliveries: [IncludedAttachmentDelivery]
    ) -> [String] {
        guard !deliveries.isEmpty else { return [] }
        return resolvedWorkers
            .filter { !$0.readsImages }
            .map { "Seat \($0.workerId) cannot receive images (non-vision)." }
    }
}
