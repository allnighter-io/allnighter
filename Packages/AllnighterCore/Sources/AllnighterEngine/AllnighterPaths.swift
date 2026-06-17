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

    /// `…/Allnighter/Pending/` — durable Draft/Pending user intent.
    public static var pending: URL {
        support.appendingPathComponent("Pending", isDirectory: true)
    }

    /// `…/Allnighter/Config/` — workers, manifests, presets.
    public static var config: URL {
        support.appendingPathComponent("Config", isDirectory: true)
    }

    /// `…/Allnighter/Coordinator/` — resident `alln serve` durable state.
    public static var coordinator: URL {
        support.appendingPathComponent("Coordinator", isDirectory: true)
    }

    /// `…/Allnighter/Evals/` — eval-harness runs, kept OUT of `Runs/` so history
    /// and `team_recall` (RB6) never surface them (contamination guard).
    public static var evals: URL {
        support.appendingPathComponent("Evals", isDirectory: true)
    }

    /// `…/Allnighter/Catalogs/` — custom team and skill definitions.
    public static var catalogs: URL {
        support.appendingPathComponent("Catalogs", isDirectory: true)
    }

    /// `…/Allnighter/Catalogs/teams/`
    public static var catalogTeams: URL {
        catalogs.appendingPathComponent("teams", isDirectory: true)
    }

    /// `…/Allnighter/Catalogs/skills/`
    public static var catalogSkills: URL {
        catalogs.appendingPathComponent("skills", isDirectory: true)
    }

    /// `…/Allnighter/ProbeScratch/` — neutral CWD for setup/health probe child
    /// processes. Setup/health probes must NOT inherit the repo or app-bundle
    /// CWD: in dev that is the checkout under `~/Documents`, so a child CLI that
    /// reads its working dir trips a TCC prompt attributed to the GUI app.
    /// (Launch Authority TCC hotfix, slice H3.) Worker/dispatch runs keep their
    /// own explicit working dirs; this is only for setup/health probes.
    public static var probeScratch: URL {
        support.appendingPathComponent("ProbeScratch", isDirectory: true)
    }

    /// Ensures `probeScratch` exists and returns its path, or `nil` if it could
    /// not be created (callers then fall back to the OS-default CWD rather than
    /// failing the probe outright).
    public static func ensuredProbeScratchPath() -> String? {
        let dir = probeScratch
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.path
        } catch {
            return nil
        }
    }
}
