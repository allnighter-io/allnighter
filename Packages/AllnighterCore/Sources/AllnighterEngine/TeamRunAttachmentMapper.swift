import Foundation
import AllnighterCore

/// Design team runs map the first image to `DesignRequest.screenshotPath`; extras
/// stay as ordered attachment paths in the seat prompt (CIA-S07).
public enum TeamRunAttachmentMapper {
    public struct MappedDesignInput: Sendable, Equatable {
        public var screenshotAbsolutePath: String?
        public var screenshotRelativePath: String?
        public var seatPromptDeliveries: [IncludedAttachmentDelivery]
    }

    public static func mapForDesign(
        deliveries: [IncludedAttachmentDelivery]
    ) -> MappedDesignInput {
        let ordered = deliveries.sorted { $0.sequence < $1.sequence }
        guard let first = ordered.first else {
            return MappedDesignInput(screenshotAbsolutePath: nil, screenshotRelativePath: nil, seatPromptDeliveries: [])
        }
        let extras = Array(ordered.dropFirst())
        return MappedDesignInput(
            screenshotAbsolutePath: first.canonicalPath,
            screenshotRelativePath: first.deliveredPathUsed,
            seatPromptDeliveries: extras
        )
    }

    public static func designSeatPrompt(
        basePrompt: String,
        deliveries: [IncludedAttachmentDelivery],
        readsImages: Bool
    ) -> String {
        let mapped = mapForDesign(deliveries: deliveries)
        var prompt = TeamRunAttachmentMapper.teamRunSeatPrompt(
            basePrompt: basePrompt,
            deliveries: mapped.seatPromptDeliveries,
            readsImages: readsImages
        )
        if let primary = mapped.screenshotRelativePath, readsImages {
            prompt = "Primary screenshot: \(primary)\n\n" + prompt
        }
        return prompt
    }

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
