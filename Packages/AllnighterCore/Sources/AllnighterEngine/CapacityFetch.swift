import Foundation
import AllnighterCore

// MARK: - CapacityFetch (CWB-S00)

/// Single live-acquire owner for capacity **display** (Engine).
///
/// - Live PTY only — never hydrates history or disk as painted truth.
/// - `warmPool` reserved for CWB-S01+ (always `nil` in S00).
/// - Freshness is owned by `CapacityResidentService` (CWB-S01a) — the S00
///   process-local display memo is retired; there is no second clock here.
public enum CapacityFetch {

    public struct Snapshot: Sendable, Equatable {
        public let now: Date
        public let windows: [CapacityWindow]
        public let rows: [CapacityBenchRow]

        public init(now: Date, windows: [CapacityWindow], rows: [CapacityBenchRow]) {
            self.now = now
            self.windows = windows
            self.rows = rows
        }
    }

    /// Launch placeholders — six `neverSampled` rows, no spawn.
    public static func launchPlaceholders(now: Date) -> [CapacityWindow] {
        CapacityAcquisition.windows(homeRoot: placeholderHome, now: now, refresh: false)
    }

    /// Live PTY acquire for all seats or one `--source` seat. Records history for
    /// analytics but **never** hydrates history into the returned windows.
    public static func liveSnapshot(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        now: Date = Date(),
        refreshSource: String? = nil,
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        probeTimeout: TimeInterval = CapacityProbe.defaultTimeout,
        probeScope: CapacityProbeScope? = nil
    ) -> Snapshot {
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            refreshSource: refreshSource,
            probeExecutor: probeExecutor,
            probeTimeout: probeTimeout,
            probeScope: probeScope
        )
        // Dashboard wave. Runs whenever the bench as a whole is refreshed, or
        // when the Go seat is the explicit target — but never when some other
        // single seat was targeted, so `--source grok` does not quietly make a
        // network request to opencode.ai.
        let wantsDashboard = refreshSource == nil
            || refreshSource == CapacityAcquisition.dogfoodSourceId
        let dashboardWindows = wantsDashboard
            ? OpenCodeGoCapacityExecutor.execute(now: now).windows
            : []
        // REPLACE the acquisition placeholder for the Go seat rather than
        // appending after it. CapacityAcquisition emits a neverSampled row for
        // every benchSourceOrder member, Go included, and the projection takes
        // the FIRST unknownReason it sees for a source. Appending therefore let
        // the placeholder win and painted a real authRequired or schemaDrift as
        // "never sampled" — inventing the CAUSE, which reads as "not set up yet"
        // and hides that the cookie is dead or the page shape moved.
        let allWindows = dashboardWindows.isEmpty
            ? windows
            : windows.filter { $0.source != CapacityAcquisition.dogfoodSourceId } + dashboardWindows
        try? historyStore.record(allWindows, now: now)
        let rows = CapacityBenchProjection.rows(from: allWindows, now: now)
        return Snapshot(now: now, windows: allWindows, rows: rows)
    }

    /// Mac launch: six never-sampled placeholders. Fresh truth lives in the
    /// resident (`CapacityResidentService.currentSnapshot()`), not here.
    public static func launchSnapshot(now: Date = Date()) -> Snapshot {
        let windows = launchPlaceholders(now: now)
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        return Snapshot(now: now, windows: windows, rows: rows)
    }

    /// Feature OFF: six honest `disabled` rows, no probe attempted.
    public static func disabledSnapshot(now: Date = Date()) -> Snapshot {
        let windows = CapacityAcquisition.benchSourceOrder.map { source in
            CapacityWindow.unknown(
                reason: .disabled,
                source: source,
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            )
        }
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        return Snapshot(now: now, windows: windows, rows: rows)
    }

    /// Dogfood OpenCode Go scrape: six `neverSampled` PTY rows + dashboard wave.
    /// When `featureEnabled` is false, returns `disabledSnapshot` with
    /// `attempted == false` diagnostics — no network, no ledger append (CWB-S01b).
    public static func dogfoodOpenCodeGoSnapshot(
        now: Date = Date(),
        featureEnabled: Bool
    ) -> (snapshot: Snapshot, diagnostics: OpenCodeGoCapacityExecutor.ScrapeDiagnostics) {
        guard featureEnabled else {
            let diagnostics = OpenCodeGoCapacityExecutor.ScrapeDiagnostics(
                attempted: false,
                ok: false,
                failureKind: "feature_disabled",
                observedAt: now
            )
            return (disabledSnapshot(now: now), diagnostics)
        }
        let six = CapacityAcquisition.windows(now: now, refresh: false)
        let outcome = OpenCodeGoCapacityExecutor.execute(now: now)
        // Same placeholder-masking hazard as liveSnapshot above: drop the
        // acquisition placeholder for the Go seat before appending the real
        // dashboard result.
        let windows = six.filter { $0.source != CapacityAcquisition.dogfoodSourceId } + outcome.windows
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        let snapshot = Snapshot(now: now, windows: windows, rows: rows)
        return (snapshot, outcome.diagnostics)
    }

    private static let placeholderHome = URL(fileURLWithPath: "/var/empty", isDirectory: true)
}
