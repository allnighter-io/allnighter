import Foundation

/// Core-owned, deterministic capability metadata for the built-in bench models.
/// Drives capability-filtered fallback before rank fallback in the resolver.
/// Until user-edited ranking exists, these defaults are the source of truth; ties
/// break by stable model id (Fanout_Team_Catalog §Model fallback is deterministic).
public enum ModelCatalog {
    public static let builtInCapabilities: [String: ModelCapabilities] = [
        "model_opus": ModelCapabilities(
            laneTags: [.build, .design, .copy],
            capabilityTags: [.code, .planner, .review, .security, .copy, .localContext],
            strengthRank: 100),
        "model_chatgpt": ModelCapabilities(
            laneTags: [.build, .design, .copy],
            capabilityTags: [.code, .planner, .review, .security],
            strengthRank: 90),
        "model_sonnet": ModelCapabilities(
            laneTags: [.build, .design, .copy],
            capabilityTags: [.code, .planner, .review, .fast],
            strengthRank: 80),
        "model_gemini": ModelCapabilities(
            laneTags: [.design, .build],
            capabilityTags: [.code, .design, .image, .fast],
            strengthRank: 75),
        "model_grok": ModelCapabilities(
            laneTags: [.build, .copy],
            capabilityTags: [.code, .planner],
            strengthRank: 70),
        "model_composer": ModelCapabilities(
            laneTags: [.build],
            capabilityTags: [.code, .fast],
            strengthRank: 60)
    ]

    /// Capabilities for a model id, or empty defaults for an unknown model.
    public static func capabilities(_ modelId: String) -> ModelCapabilities {
        builtInCapabilities[modelId] ?? ModelCapabilities()
    }
}
