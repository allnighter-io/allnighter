import Foundation

/// Core-owned support-dir resolution (mirrors `AllnighterEngine.AllnighterPaths.support`).
/// Catalog + roster persistence in Core must honor `ALLNIGHTER_SUPPORT_DIR` the same
/// way engine stores do — otherwise isolated config homes split roster state.
public enum AllnighterSupportRoot {
    public static var support: URL {
        if let override = ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }

        // There is ONE durable state root. A restricted host (e.g. Codex, whose
        // sandbox denies writes outside its workspace) used to be redirected here
        // to a per-thread temp tree, which silently gave that host a different
        // product: no projects, no teams, no runs. That is an alternate state
        // root — the same forbidden shape as a project mirror, one layer down —
        // and it is the most plausible seed of the Code Red incident, because an
        // agent that sees an empty catalog concludes the real repository is
        // unreachable. A host that cannot write this root must fail honestly
        // (RUN_JOURNAL_UNAVAILABLE) and be granted access, never be handed a
        // parallel world. See docs/archive/phases/CODE_RED_Core_Infrastructure_Repair.md.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Allnighter", isDirectory: true)
    }

    public static var config: URL {
        support.appendingPathComponent("Config", isDirectory: true)
    }

    /// `…/Allnighter/Release/` — OPC-S06 release-channel cache (mirrors Engine path).
    public static var release: URL {
        support.appendingPathComponent("Release", isDirectory: true)
    }
}
