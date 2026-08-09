import Foundation
import AllnighterCore

/// Serve-hosted capacity refresh — so the bench knows its own quota without the
/// Mac app being open.
///
/// Founder ruling 2026-08-08 (`docs/phases/Probe_Freshness.md` §0.2):
/// *"Scheduler requiring app to be open feels like 100% the WRONG call."*
/// Before this, `CapacityResidentService` (started at `AllnighterMacApp`) was the
/// **only** automatic producer of capacity data anywhere — app closed meant no
/// refresh at all, and every reading aged until someone opened the app.
///
/// ## Why there is no lock
///
/// Both the Dock app's resident and this scheduler write durable history through
/// `CapacityFetch.liveSnapshot`, which records every acquisition
/// (`CapacityFetch.swift`). So **history recency is already a shared,
/// cross-process freshness signal**, and the scheduler needs no lease, socket, or
/// arbiter to avoid double-probing:
///
/// - app open and refreshing → history stays fresh → this loop does nothing;
/// - app closed → history goes stale → this loop refreshes.
///
/// That matters beyond tidiness. Two processes probing at once means two waves of
/// interactive vendor TUIs competing for the machine, and capacity probes are
/// measurably load-sensitive: on 2026-08-08 a loaded box turned a 6-second
/// full-bench refresh into 2-of-6 failures. An arbiter that can drift is worse
/// than a question both sides can answer from the same durable fact.
///
/// A simultaneous start is still possible and is deliberately tolerated: the
/// worst case is one wasted refresh, not corruption. `CapacityHistoryStore`
/// documents that it accepts unlocked concurrent writers and heals on the next
/// observation.
public struct CapacityRefreshScheduler: Sendable {

    /// How often to *check*. Deliberately much shorter than the freshness
    /// window, so a refresh lands promptly after the app quits rather than up to
    /// a full window later.
    public static let tickInterval: TimeInterval = 5 * 60

    /// Serve-side only — paint/CLI freshness disclosure still uses
    /// `CapacityPaintGate.gateInterval` alone (invariant 3). This margin
    /// gives the app's in-flight probe time to commit history before serve
    /// treats the window as unclaimed.
    public static let serveFreshnessMargin: TimeInterval = 2 * 60

    /// Positive-only jitter dephases the serve tick from the app's 30m
    /// deadline over a few cycles. Same semantics as
    /// `DefaultPendingWakeSleeper.sleep`.
    public var tickJitterSeconds: TimeInterval

    public var featureSettings: CapacityFeatureSettingsPersistence
    public var historyStore: CapacityHistoryStore
    /// Injected so tests never spawn a vendor TUI.
    public var refresh: @Sendable () -> Void
    public var now: @Sendable () -> Date
    public var sleeper: any PendingWakeSleeper

    public init(
        featureSettings: CapacityFeatureSettingsPersistence = CapacityFeatureSettingsPersistence(),
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        refresh: (@Sendable () -> Void)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        sleeper: any PendingWakeSleeper = DefaultPendingWakeSleeper(),
        tickJitterSeconds: TimeInterval = 60
    ) {
        self.featureSettings = featureSettings
        self.historyStore = historyStore
        self.refresh = refresh ?? { _ = CapacityFetch.liveSnapshot() }
        self.now = now
        self.sleeper = sleeper
        self.tickJitterSeconds = tickJitterSeconds
    }

    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        while !isCancelled() {
            if shouldRefresh(at: now()) {
                refresh()
            }
            do {
                try await sleeper.sleep(
                    until: now().addingTimeInterval(Self.tickInterval),
                    jitterSeconds: tickJitterSeconds)
            } catch { break }
        }
    }

    /// True when nothing has observed capacity within the freshness window.
    ///
    /// Feature OFF means zero probes from every trigger (CWB-S01b) — a
    /// background scheduler is not an exception to that, and must not spend the
    /// user's quota while the feature is switched off.
    public func shouldRefresh(at instant: Date) -> Bool {
        guard featureSettings.loadEnabled() else { return false }
        guard let newest = newestObservation(at: instant) else {
            // Never sampled at all — refresh, that is the whole point.
            return true
        }
        return instant.timeIntervalSince(newest)
            >= CapacityPaintGate.gateInterval + Self.serveFreshnessMargin
    }

    /// Newest observation across every bench source, or nil when history is
    /// empty. One clock, shared with capacity paint and probe freshness — a
    /// second constant here would be a second thing to explain the moment the
    /// two disagree.
    public func newestObservation(at instant: Date) -> Date? {
        historyStore
            .lastKnownWindows(now: instant)
            .map(\.observedAt)
            .max()
    }
}
