import Foundation
import AllnighterCore

/// Deterministic routing: regular chat invoke vs `imageGen` profile for one-worker chat.
public enum ChatImageIntent: Sendable {
    public enum Profile: Sendable, Equatable {
        case regularText
        case imageGen
    }

    private static let explicitImagePhrases = [
        "generate image", "generate an image", "make an image", "draw ", "render ",
        "screenshot", "new visual", "return an updated mockup", "updated mockup",
        "create an image", "produce an image", "make a picture", "generate a picture",
    ]

    private static let visualEditPhrases = [
        "make it bolder", "make the header bolder", "dark mode", "more whitespace",
        "try this in", "more like this", "try it in", "bolder header", "more contrast",
        "lighter background", "darker background", "increase contrast", "less cluttered",
    ]

    /// Select `imageGen` when the manifest declares it and the user message matches
    /// an explicit image request, or a visual edit with prior image context.
    public static func decide(
        message: String,
        manifest: DriverManifest,
        hasPriorImageContext: Bool
    ) -> Profile {
        guard manifest.imageGen != nil else { return .regularText }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return .regularText }

        if explicitImagePhrases.contains(where: { normalized.contains($0) }) {
            return .imageGen
        }
        if hasPriorImageContext, visualEditPhrases.contains(where: { normalized.contains($0) }) {
            return .imageGen
        }
        return .regularText
    }
}
