import Foundation

/// Frozen public run lifecycle (RLR-L3). The single wire vocabulary for
/// status, `--wait-for`, `ps` rows, and every JSON/NDJSON projection. Durable
/// `RunStatus` (with its multi-worker stage names) projects onto this via
/// `RunStatus.lifecycle`; nothing on disk stores `RunLifecycle` directly.
public enum RunLifecycle: String, Codable, Sendable, CaseIterable {
    case queued, running, done, failed, timedOut, cancelled

    public var isTerminal: Bool {
        switch self {
        case .queued, .running:
            return false
        case .done, .failed, .timedOut, .cancelled:
            return true
        }
    }
}

/// Frozen public phase axis (RLR-L3). Only meaningful for non-terminal runs;
/// terminal runs omit `phase`. `queued` runs are `waitingForWriteLock` or
/// `spawningWorker`; `running` runs are `working`, `proving`, or `settling`.
public enum RunPhase: String, Codable, Sendable, CaseIterable {
    case waitingForWriteLock, spawningWorker   // lifecycle == .queued
    case working, proving, settling            // lifecycle == .running

    /// The lifecycle this phase is legal under (RLR-L3 phase table).
    public var lifecycle: RunLifecycle {
        switch self {
        case .waitingForWriteLock, .spawningWorker:
            return .queued
        case .working, .proving, .settling:
            return .running
        }
    }
}

/// Named finite clock defaults (RLR-L8, S01c). **S01 only names these
/// defaults; S05 wires the `--handshake-timeout` / `--first-activity-timeout`
/// / `--wall-timeout` CLI flags and fires the clocks against them — no
/// enforcement here.** Per-repo overrides are read from `Config/Tool/config.json`
/// (the same override home as `ToolConfig`) once S05 lands the config fields;
/// today these are the product-wide defaults with no override path yet.
///
/// `--idle-timeout` is deliberately absent here: RLR-L8 keeps its current
/// product default unchanged (per-driver-manifest `timeoutSeconds`, e.g.
/// grok=1800s — see `DefaultConfig.manifests`), not a single named constant.
public enum RunClockDefaults {
    /// Runner-ready handshake bound (`--handshake-timeout`, S05). Matches the
    /// existing internal order of `ProcessOwnership.waitForRunnerReady`.
    public static let handshakeTimeoutSeconds: Double = 60

    /// First post-spawn activity bound (`--first-activity-timeout`, S05). 2×
    /// the handshake bound — headroom for cold model warmup after spawn.
    public static let firstActivityTimeoutSeconds: Double = 120

    /// Total wall-clock ceiling (`--wall-timeout`, S05). Longer than the
    /// longest driver-manifest idle timeout (1800s, grok) so it never
    /// pre-empts a healthy long-running worker.
    public static let wallTimeoutSeconds: Double = 3600

    /// Every default above must be finite — a clock that can silently become
    /// "wait forever" defeats RLR-L8. Exercised by `LegacyJournalTests`.
    public static var allFinite: Bool {
        [handshakeTimeoutSeconds, firstActivityTimeoutSeconds, wallTimeoutSeconds]
            .allSatisfy { $0.isFinite && $0 > 0 }
    }
}
