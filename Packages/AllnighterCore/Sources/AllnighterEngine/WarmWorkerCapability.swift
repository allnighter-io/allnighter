import Foundation

/// Which driver sources can run as a WARM persistent worker via ACP-over-stdio
/// (Warm_Single_Lane_Chat §5). Declarative + code-level so it extends per CLI as each is validated;
/// a source NOT here transparently uses the existing cold per-turn spawn (no regression).
public enum WarmWorkerCapability {
    /// Sources proven to speak ACP over stdio. grok = `grok agent stdio`; cursor = `agent acp`.
    public static let acpStdioSources: Set<String> = ["grok", "cursor_agent"]

    public static func supportsACPStdio(_ sourceId: String) -> Bool {
        acpStdioSources.contains(sourceId)
    }
}
