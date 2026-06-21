import Foundation
import AllnighterCore

/// Renders the protected attachment block for worker prompts (law §5).
public enum AttachmentDeliveryRenderer {
    public static let nonVisionNotice = """
[System Notice: The user attached an image to this turn, but your model configuration does not support image viewing. Rely on the user's text below. Do not claim to see the image.]
"""

    /// Path block sorted by `sequence` for vision-capable workers (images only).
    public static func pathBlock(deliveries: [IncludedAttachmentDelivery]) -> String {
        let ordered = deliveries.filter { $0.deliveryKind == .image }.sorted { $0.sequence < $1.sequence }
        guard !ordered.isEmpty else { return "" }
        var lines = ["Attached images (use these paths):"]
        for (index, delivery) in ordered.enumerated() {
            lines.append("\(index + 1). \(delivery.deliveredPathUsed) (sha256: \(delivery.storedSha256))")
        }
        return lines.joined(separator: "\n")
    }

    /// Path block for attached TEXT files — readable by ANY worker (no vision gate), so a
    /// couple of pasted snippets become files to open instead of inline prompt bloat.
    public static func textPathBlock(deliveries: [IncludedAttachmentDelivery]) -> String {
        let ordered = deliveries.filter { $0.deliveryKind == .text }.sorted { $0.sequence < $1.sequence }
        guard !ordered.isEmpty else { return "" }
        var lines = ["Attached text files (read these paths for full context):"]
        for (index, delivery) in ordered.enumerated() {
            lines.append("\(index + 1). \(delivery.deliveredPathUsed)")
        }
        return lines.joined(separator: "\n")
    }

    /// Join the per-kind blocks for a worker prompt: images branch on vision, text is
    /// always a read-paths block.
    private static func combinedBlock(deliveries: [IncludedAttachmentDelivery], readsImages: Bool) -> String {
        var blocks: [String] = []
        let hasImages = deliveries.contains { $0.deliveryKind == .image }
        if hasImages {
            blocks.append(readsImages ? pathBlock(deliveries: deliveries) : nonVisionNotice)
        }
        let textBlock = textPathBlock(deliveries: deliveries)
        if !textBlock.isEmpty { blocks.append(textBlock) }
        return blocks.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Full prompt body: base context + protected attachment block.
    public static func protectedPrompt(
        baseText: String,
        deliveries: [IncludedAttachmentDelivery],
        readsImages: Bool,
        byteCap: Int
    ) throws -> String {
        let block = deliveries.isEmpty ? "" : combinedBlock(deliveries: deliveries, readsImages: readsImages)

        guard block.isEmpty else {
            let combined = baseText + "\n\n" + block
            if combined.utf8.count > byteCap { throw AttachmentError.contextCapExceeded }
            return combined
        }
        if baseText.utf8.count > byteCap { throw AttachmentError.contextCapExceeded }
        return baseText
    }

    /// Per-worker prompt with vision/non-vision branching (CIA-S07 base).
    public static func teamRunSeatPrompt(
        basePrompt: String,
        deliveries: [IncludedAttachmentDelivery],
        readsImages: Bool
    ) -> String {
        if deliveries.isEmpty { return basePrompt }
        let block = combinedBlock(deliveries: deliveries, readsImages: readsImages)
        return block.isEmpty ? basePrompt : basePrompt + "\n\n" + block
    }
}
