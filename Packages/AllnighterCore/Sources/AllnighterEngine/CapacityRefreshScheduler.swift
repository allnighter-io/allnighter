import Foundation
import AllnighterCore

/// CRS-S04: bench-level refresh verdict for backoff (invariant 7).
/// Partial success (≥1 durable source) resets the backoff; the still-failed
/// sources are retried per S03's per-source window, not here.
public enum CapacityRefreshAttempt: Sendable, Equatable {
    case durableSuccess
    case benchFailure
}

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
    /// Factory for per-refresh `CapacityProbeScope` (CRS-S01). Same shape as
    /// `CapacityResidentService.makeScope`. Tests inject a spy terminator so
    /// scoped-kill wiring proofs stay deterministic.
    public var makeScope: @Sendable () -> CapacityProbeScope
    /// Injected so tests never spawn a vendor TUI.
    /// CRS-S01: signature widened to accept the per-refresh scope so
    /// liveSnapshot can register probe children into it.
    /// CRS-S04: async so `terminate()` interrupts an in-flight probe
    /// (scope-kill unlocks mid-probe kill). Returns the attempt verdict for
    /// bench-level backoff (invariant 7).
    public var refresh: @Sendable (CapacityProbeScope) async -> CapacityRefreshAttempt
    public var now: @Sendable () -> Date
    public var sleeper: any PendingWakeSleeper

    public init(
        featureSettings: CapacityFeatureSettingsPersistence = CapacityFeatureSettingsPersistence(),
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        makeScope: @escaping @Sendable () -> CapacityProbeScope = { CapacityProbeScope() },
        refresh: (@Sendable (CapacityProbeScope) async -> CapacityRefreshAttempt)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        sleeper: any PendingWakeSleeper = DefaultPendingWakeSleeper(),
        tickJitterSeconds: TimeInterval = 60
    ) {
        self.featureSettings = featureSettings
        self.historyStore = historyStore
        self.makeScope = makeScope
        self.refresh = refresh ?? Self.defaultRefresh(historyStore: historyStore)
        self.now = now
        self.sleeper = sleeper
        self.tickJitterSeconds = tickJitterSeconds
    }

    private static func defaultRefresh(
        historyStore: CapacityHistoryStore
    ) -> @Sendable (CapacityProbeScope) async -> CapacityRefreshAttempt {
        { scope in
            let snap = CapacityFetch.liveSnapshot(historyStore: historyStore, probeScope: scope)
            if snap.historyWriteFailed { return .benchFailure }
            let anyDurable = snap.windows.contains { $0.unknownReason == nil }
            return anyDurable ? .durableSuccess : .benchFailure
        }
    }

    /// CRS-S04: async refresh with cooperative cancellation and bench-level
    /// exponential backoff (invariant 7). Cancellation is by pre/post-await
    /// `isCancelled` checks + `inFlight.terminateIfHeld()`.
    ///
    /// Honest limitation: without a sibling cancel poller, `scope.terminate()`
    /// still runs after `await refresh` returns (same semantics as S01 before
    /// the await). Mid-probe scope-kill (calling `terminateIfHeld()` while the
    /// refresh is in flight, terminating probe PIDs so `liveSnapshot` returns
    /// promptly) requires a concurrent poller task; that is deferred to a
    /// follow-up slice because the poller's `isCancelled()` calls eat test
    /// ticks. The async await alone is still worth shipping — it frees the
    /// cooperative thread pool during refresh and enables the backoff.
    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        let inFlight = InFlightScopeBox()
        var consecutiveBenchFailures = 0

        while !isCancelled() {
            let didRefresh: Bool
            if shouldRefresh(at: now()) {
                didRefresh = true
                let scope = makeScope()
                if isCancelled() {
                    // Cancelled before refresh could start — still terminate
                    // so we don't leak a scope.
                    scope.terminate()
                    inFlight.terminateIfHeld()
                    break
                }
                inFlight.store(scope)
                let result = await refresh(scope)
                if isCancelled() {
                    inFlight.terminateIfHeld()
                }
                scope.terminate()
                inFlight.clear()

                switch result {
                case .durableSuccess:
                    consecutiveBenchFailures = 0
                case .benchFailure:
                    consecutiveBenchFailures += 1
                }
            } else {
                didRefresh = false
            }

            if isCancelled() {
                inFlight.terminateIfHeld()
                break
            }

            let sleepUntil: Date
            if didRefresh && consecutiveBenchFailures > 0 {
                let backoff = Self.backoffDuration(failureCount: consecutiveBenchFailures)
                sleepUntil = now().addingTimeInterval(backoff)
            } else {
                sleepUntil = now().addingTimeInterval(Self.tickInterval)
            }

            do {
                try await sleeper.sleep(until: sleepUntil, jitterSeconds: tickJitterSeconds)
            } catch { break }
        }
        inFlight.terminateIfHeld()
    }

    /// Exponential backoff capped at `CapacityPaintGate.gateInterval`.
    /// 5 → 10 → 20 → 30m (cap), per invariant 7.
    static func backoffDuration(failureCount: Int) -> TimeInterval {
        let base: TimeInterval = 5 * 60
        let raw = base * pow(2.0, Double(failureCount - 1))
        return min(CapacityPaintGate.gateInterval, raw)
    }

    /// Thread-safe box so the cancel path can reach the in-flight scope.
    /// CRS-S04: the post-await `isCancelled` check calls `terminateIfHeld()`
    /// after `await refresh` returns. Mid-probe kill (calling terminate while
    /// refresh is still in flight) requires a concurrent poller task, deferred
    /// to a follow-up slice.
    private final class InFlightScopeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var scope: CapacityProbeScope?

        func store(_ scope: CapacityProbeScope) {
            lock.lock(); self.scope = scope; lock.unlock()
        }

        func clear() {
            lock.lock(); scope = nil; lock.unlock()
        }

        func terminateIfHeld() {
            lock.lock()
            let s = scope
            scope = nil
            lock.unlock()
            s?.terminate()
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
