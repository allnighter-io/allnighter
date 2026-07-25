import Foundation

/// Canonical on-disk locations under Application Support (see `00` §7). All
/// engine stores resolve their roots here so runs, presets, and config share one
/// `Allnighter/` tree and tests can redirect by passing explicit roots.
public enum AllnighterPaths {
    /// `~/Library/Application Support/Allnighter/`
    public static var support: URL {
        if let override = ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }

        // ONE durable state root, for every host. The Codex per-thread temp
        // fallback that used to live here is deleted: it handed a restricted host
        // a parallel, empty product instead of failing honestly. This mirrors
        // AllnighterSupportRoot (Engine cannot depend on Core) — keep them
        // identical. See docs/archive/phases/CODE_RED_Core_Infrastructure_Repair.md.
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

    /// `…/Allnighter/Projects/` — durable Project records (the work-floor spine).
    public static var projects: URL {
        support.appendingPathComponent("Projects", isDirectory: true)
    }

    /// `…/Allnighter/ProjectReadiness/` — cached per-Project worker readiness
    /// (PRJ-S07b). Allnighter's own cache; never vendor config. One file per project.
    public static var projectReadiness: URL {
        support.appendingPathComponent("ProjectReadiness", isDirectory: true)
    }

    /// `…/Allnighter/Config/` — workers, manifests, presets.
    public static var config: URL {
        support.appendingPathComponent("Config", isDirectory: true)
    }

    /// `…/Allnighter/Config/Remote/` — remote pairing credentials and agent keys.
    public static var remote: URL {
        config.appendingPathComponent("Remote", isDirectory: true)
    }

    /// `…/Allnighter/Coordinator/` — resident `alln serve` durable state.
    public static var coordinator: URL {
        support.appendingPathComponent("Coordinator", isDirectory: true)
    }

    public static var stalled: URL {
        support.appendingPathComponent("Stalled", isDirectory: true)
    }

    /// `…/Allnighter/Relays/` — durable PM Relay state (`docs/phases/PM_Relay.md`), one
    /// folder per relay (`relays/<id>/relay.json`), mirroring the `Runs/` layout.
    public static var relays: URL {
        support.appendingPathComponent("Relays", isDirectory: true)
    }

    /// `…/Allnighter/Evals/` — eval-harness runs, kept OUT of `Runs/` so history
    /// and `team_recall` (RB6) never surface them (contamination guard).
    public static var evals: URL {
        support.appendingPathComponent("Evals", isDirectory: true)
    }

    /// `…/Allnighter/Lanes/` — per-root execution-lane flock + holder metadata
    /// (`docs/phases/Process_Ownership.md` PO-S03b). One directory per lane key.
    ///
    /// **PO-S04 persistent scratch:** each lane key also owns
    /// `…/Lanes/<key>/scratch/` — one warm SwiftPM scratch for harness proofs on
    /// that root (not per-attempt). See `ExecutionLaneFlock.scratchDirectory(forLaneKey:)`.
    public static var lanes: URL {
        support.appendingPathComponent("Lanes", isDirectory: true)
    }

    /// `…/Allnighter/Logs/` — plain-text operational logs a founder can read
    /// without Console (today: the sandbox hand-off lifecycle).
    public static var logs: URL {
        support.appendingPathComponent("Logs", isDirectory: true)
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

    /// `…/Allnighter/Catalogs/models/`
    public static var catalogModels: URL {
        catalogs.appendingPathComponent("models", isDirectory: true)
    }

    /// `…/Allnighter/Recipes/` — ONB-S02b mirror of bundled recipe `.md` cards
    /// (shipped content; overwritten from the Core bundle on app update). Finder /
    /// agents read this path; `RecipeCatalog` remains the read SSOT.
    public static var recipes: URL {
        support.appendingPathComponent("Recipes", isDirectory: true)
    }

    /// `…/Allnighter/ProbeScratch/` — neutral CWD for setup/health probe child
    /// processes. Setup/health probes must NOT inherit the repo or app-bundle
    /// CWD: in dev that is the checkout under `~/Documents`, so a child CLI that
    /// reads its working dir trips a TCC prompt attributed to the GUI app.
    /// (Launch Authority TCC hotfix, slice H3.) Worker/repo runs keep their
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
