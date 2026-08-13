import Foundation
import AllnighterCore

/// Canonical on-disk locations under Application Support (see `00` §7). All
/// engine stores resolve their roots here so runs, presets, and config share one
/// `Allnighter/` tree. Explicit tests may still set `ALLNIGHTER_SUPPORT_DIR`;
/// XCTest hosts are redirected automatically via `AllnighterSupportRoot`.
public enum AllnighterPaths {
    /// When the XCTest support-root redirect is active (see
    /// `AllnighterSupportRoot.activeTestSupportRoot`).
    public static var activeTestSupportRoot: URL? {
        AllnighterSupportRoot.activeTestSupportRoot
    }

    /// `~/Library/Application Support/Allnighter/` in production; a per-process
    /// temp directory under XCTest. Single resolver: `AllnighterSupportRoot`.
    public static var support: URL {
        AllnighterSupportRoot.support
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

    /// `…/Allnighter/Loops/` — durable loop state, one folder per loop
    /// (`Loops/<id>/relay.json`), mirroring the `Runs/` layout. On-disk `relay.json`
    /// filenames are unchanged (wire-stable); only the parent directory moved from
    /// `Relays/` (LVC-S09).
    public static var loops: URL {
        support.appendingPathComponent("Loops", isDirectory: true)
    }

    /// `…/Allnighter/Sweeps/` — durable sweep queues (`Sweeps/<id>/sweep.json`).
    public static var sweeps: URL {
        support.appendingPathComponent("Sweeps", isDirectory: true)
    }

    /// Pre-LVC-S09 loop state directory. Used only to detect a silent empty list after
    /// the `Relays/` → `Loops/` path move — never read for normal operation.
    public static var legacyRelaysDirectory: URL {
        support.appendingPathComponent("Loops", isDirectory: true)
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

    /// `…/Allnighter/Capacity/` — per-source capacity window history (CAP-S05).
    /// One JSON file per source id; never PII or raw vendor snippets.
    public static var capacity: URL {
        support.appendingPathComponent("Capacity", isDirectory: true)
    }

    /// `…/Allnighter/Capacity/capacity.sock` — CWB-S02 read-only resident
    /// snapshot endpoint. Bound by the Dock app while it runs, unlinked on
    /// graceful quit; a stale file after a hard kill is reconciled by
    /// unlink-before-bind at the next launch.
    public static var capacitySocket: URL {
        capacity.appendingPathComponent("capacity.sock")
    }

    /// `…/Allnighter/Release/` — cached release-channel check (OPC-S06).
    /// Product SSOT for "is there a newer release?" is remote `latest.json`;
    /// this directory holds only the local fail-open cache (`latest-check.json`).
    public static var release: URL {
        support.appendingPathComponent("Release", isDirectory: true)
    }

    /// `…/Allnighter/Release/latest-check.json`
    public static var releaseCheckCache: URL {
        release.appendingPathComponent("latest-check.json")
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
    /// (Launch Authority TCC hotfix, slice H3.) Agent/repo runs keep their
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
