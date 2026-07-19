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
/// terminal runs omit `phase`. `queued` runs are `waitingForVendor`,
/// `waitingForWriteLock`, or `spawningWorker`; `running` runs are `working`,
/// `proving`, or `settling`.
public enum RunPhase: String, Codable, Sendable, CaseIterable {
    case waitingForVendor, waitingForWriteLock, spawningWorker // lifecycle == .queued
    case working, proving, settling                         // lifecycle == .running

    /// The lifecycle this phase is legal under (RLR-L3 phase table).
    public var lifecycle: RunLifecycle {
        switch self {
        case .waitingForVendor, .waitingForWriteLock, .spawningWorker:
            return .queued
        case .working, .proving, .settling:
            return .running
        }
    }
}

/// Named finite clock defaults (RLR-L8, S01c). S05 wires the CLI flags and
/// fires the clocks against them via `RunClockEnforcer`. Per-repo overrides
/// may later read `Config/Tool/config.json` (same home as `ToolConfig`); today
/// these are the product-wide defaults.
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

/// Per-run clock budgets persisted on the journal (RLR-L8 / S05) so a second
/// process / `status` can reason about them without re-parsing CLI flags.
public struct RunClockBudgets: Codable, Equatable, Sendable {
    public var handshakeTimeoutSeconds: Double
    public var firstActivityTimeoutSeconds: Double
    /// `nil` = driver-manifest idle (RLR-L8 keeps the per-manifest default).
    public var idleTimeoutSeconds: Double?
    public var wallTimeoutSeconds: Double

    public init(
        handshakeTimeoutSeconds: Double = RunClockDefaults.handshakeTimeoutSeconds,
        firstActivityTimeoutSeconds: Double = RunClockDefaults.firstActivityTimeoutSeconds,
        idleTimeoutSeconds: Double? = nil,
        wallTimeoutSeconds: Double = RunClockDefaults.wallTimeoutSeconds
    ) {
        self.handshakeTimeoutSeconds = handshakeTimeoutSeconds
        self.firstActivityTimeoutSeconds = firstActivityTimeoutSeconds
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.wallTimeoutSeconds = wallTimeoutSeconds
    }

    /// Resolve CLI overrides (seconds) onto named defaults. Idle stays optional.
    public static func resolved(
        handshake: Int? = nil,
        firstActivity: Int? = nil,
        idle: Int? = nil,
        wall: Int? = nil
    ) -> RunClockBudgets {
        RunClockBudgets(
            handshakeTimeoutSeconds: Double(handshake ?? Int(RunClockDefaults.handshakeTimeoutSeconds)),
            firstActivityTimeoutSeconds: Double(
                firstActivity ?? Int(RunClockDefaults.firstActivityTimeoutSeconds)),
            idleTimeoutSeconds: idle.map(Double.init),
            wallTimeoutSeconds: Double(wall ?? Int(RunClockDefaults.wallTimeoutSeconds))
        )
    }
}

/// Which of the four RLR-L8 clocks fired.
public enum RunClockKind: String, Codable, Sendable, CaseIterable {
    case handshake
    case firstActivity
    case idle
    case wall
}
