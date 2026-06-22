import Foundation

/// Which driver sources can run as a WARM persistent worker via ACP-over-stdio
/// (Warm_Single_Lane_Chat §5). Declarative + code-level so it extends per CLI as each is validated;
/// a source NOT here transparently uses the existing cold per-turn spawn (no regression).
public enum WarmWorkerCapability {
    /// Sources proven to run a warm persistent worker over stdio. grok = `grok agent stdio` (ACP);
    /// cursor = `agent acp` (ACP); codex = `codex app-server`; claude = `claude -p --input-format
    /// stream-json`. Each has its own `WarmSessionDriver` dialect.
    public static let acpStdioSources: Set<String> = ["grok", "cursor_agent", "codex", "claude_code"]

    /// EXCEPTION — `antigravity` (`agy`) is intentionally absent: it has NO warm mode (no
    /// daemon/server/stdio protocol; `--conversation` resume is a cold start every turn). The only
    /// warm option is the `google-antigravity` Python SDK — not worth a second transport + a Python
    /// dependency for a source used almost entirely as an async worker. It uses the hardened cold
    /// spawn (skip-permissions + vendor_session resume). See docs/phases/Warm_Single_Lane_Chat.md §5,
    /// Phase 5. Revisit only if agy becomes a heavy interactive-chat source.

    public static func supportsACPStdio(_ sourceId: String) -> Bool {
        acpStdioSources.contains(sourceId)
    }
}
