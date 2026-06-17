import Foundation
import AllnighterCore

/// Renders the protected attachment block for worker prompts (law §5).
public enum AttachmentDeliveryRenderer {
    public static let nonVisionNotice = """
[System Notice: The user attached an image to this turn, but your model configuration does not support image viewing. Rely on the user's text below. Do not claim to see the image.]
"""

    /// Path block sorted by `sequence` for vision-capable workers.
    public static func pathBlock(deliveries: [IncludedAttachmentDelivery]) -> String {
        let ordered = deliveries.sorted { $0.sequence < $1.sequence }
        guard !ordered.isEmpty else { return "" }
        var lines = ["Attached images (use these paths):"]
        for (index, delivery) in ordered.enumerated() {
            lines.append("\(index + 1). \(delivery.deliveredPathUsed) (sha256: \(delivery.storedSha256))")
        }
        return lines.joined(separator: "\n")
    }

    /// Full prompt body: base context + protected attachment block.
    public static func protectedPrompt(
        baseText: String,
        deliveries: [IncludedAttachmentDelivery],
        readsImages: Bool,
        byteCap: Int
    ) throws -> String {
        let block: String
        if readsImages {
            block = pathBlock(deliveries: deliveries)
        } else if deliveries.isEmpty {
            block = ""
        } else {
            block = nonVisionNotice
        }

        guard block.isEmpty else {
            let combined = baseText + "\n\n" + block
            if combined.utf8.count > byteCap { throw AttachmentError.contextCapExceeded }
            return combined
        }
        if baseText.utf8.count > byteCap { throw AttachmentError.contextCapExceeded }
        return baseText
    }

    /// Per-seat fan-out prompt with vision/non-vision branching (CIA-S07 base).
    public static func fanoutSeatPrompt(
        basePrompt: String,
        deliveries: [IncludedAttachmentDelivery],
        readsImages: Bool
    ) -> String {
        if readsImages {
            let block = pathBlock(deliveries: deliveries)
            return block.isEmpty ? basePrompt : basePrompt + "\n\n" + block
        }
        if deliveries.isEmpty { return basePrompt }
        return basePrompt + "\n\n" + nonVisionNotice
    }
}
