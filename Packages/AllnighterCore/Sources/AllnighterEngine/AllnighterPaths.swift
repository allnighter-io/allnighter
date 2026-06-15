import Foundation

/// Canonical on-disk locations under Application Support (see `00` §7). All
/// engine stores resolve their roots here so runs, presets, and config share one
/// `Allnighter/` tree and tests can redirect by passing explicit roots.
public enum AllnighterPaths {
    /// `~/Library/Application Support/Allnighter/`
    public static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Allnighter", isDirectory: true)
    }

    /// `…/Allnighter/Runs/`
    public static var runs: URL {
        support.appendingPathComponent("Runs", isDirectory: true)
    }

    /// `…/Allnighter/Threads/` — persistent work threads (turns own chat; heavy
    /// turns reference runs under `Runs/` by id).
    public static var threads: URL {
        support.appendingPathComponent("Threads", isDirectory: true)
    }

    /// `…/Allnighter/Config/` — workers, manifests, presets.
    public static var config: URL {
        support.appendingPathComponent("Config", isDirectory: true)
    }

    /// `…/Allnighter/Evals/` — eval-harness runs, kept OUT of `Runs/` so history
    /// and `council_recall` (RB6) never surface them (contamination guard).
    public static var evals: URL {
        support.appendingPathComponent("Evals", isDirectory: true)
    }
}
