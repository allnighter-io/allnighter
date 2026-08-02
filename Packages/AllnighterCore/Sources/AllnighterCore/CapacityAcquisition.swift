import Foundation

/// Capacity acquisition boundary — **PTY only, all six bench seats** (CWB-S00).
///
/// Every seat uses one cold PTY probe adapter on refresh. There is no disk/log
/// path for capacity display — live probe or `neverSampled` / unknown.
///
/// **Bare call** (`refresh: false`) — every seat is `neverSampled`. No probes.
///
/// **Refresh** (`refresh: true`) — run PTY adapters for all seats (or one with
/// `refreshSource`). Never idle-backgrounded; only explicit refresh starts probes.
///
/// Injectable `homeRoot` / `probeExecutor` keep tests off the real home and off
/// real vendor CLIs.
///
/// Fail closed: spawn failure, timeout, empty capture, and parse failure all
/// return `unknown` with a reason — never throw, never invent 0%.
public enum CapacityAcquisition {

    /// Fixed product display order (source ids). Not-ready/parked seats are
    /// reordered by the strip renderer, not here.
    public static let benchSourceOrder: [String] = [
        "codex",
        "claude_code",
        "cursor_agent",
        "grok",
        "kimi",
        "agy",
    ]

    /// Retired — disk is not a capacity display path (CWB-S00). Kept empty so
    /// stale call sites fail compile or tests rather than silently routing to disk.
    public static let diskOnlySources: [String] = []

    /// All bench seats are PTY-probed on refresh.
    public static let ptyOnlySources: [String] = benchSourceOrder

    /// Full bench roster. Prefer `benchSourceOrder` for display order.
    public static let tier3DisklessSources: [String] = benchSourceOrder

    /// PTY seats driven on refresh — all six.
    public static let tier3ProbeableSources: [String] = benchSourceOrder

    /// Valid bench source ids for targeted refresh.
    public static var validRefreshSourceIds: [String] { benchSourceOrder }

    /// CLI_USAGE_ERROR message when `--source` is unknown / misspelled.
    public static func unknownRefreshSourceMessage(_ id: String) -> String {
        let valid = validRefreshSourceIds.joined(separator: ", ")
        return "unknown source: \(id) (valid: \(valid))"
    }

    /// `nil` when `id` is a known bench source; otherwise the usage error message.
    public static func validateRefreshSourceId(_ id: String) -> String? {
        guard validRefreshSourceIds.contains(id) else {
            return unknownRefreshSourceMessage(id)
        }
        return nil
    }

    /// PTY sources that will be attempted on this refresh (empty when `refresh` is false).
    public static func sourcesProbed(
        refresh: Bool,
        refreshSource: String? = nil
    ) -> [String] {
        guard refresh else { return [] }
        if let refreshSource {
            return benchSourceOrder.contains(refreshSource) ? [refreshSource] : []
        }
        return benchSourceOrder
    }

    /// Acquire capacity windows for the fixed bench under `homeRoot`.
    public static func windows(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        now: Date,
        refresh: Bool = false,
        refreshSource: String? = nil,
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        probeTimeout: TimeInterval = CapacityProbe.defaultTimeout
    ) -> [CapacityWindow] {
        _ = homeRoot // reserved for warm-pool / resident cache (CWB-S01+)
        let sourcesToProbe = Set(sourcesProbed(refresh: refresh, refreshSource: refreshSource))

        if sourcesToProbe.isEmpty {
            return orderedBenchWindows(
                Dictionary(
                    uniqueKeysWithValues: benchSourceOrder.map { source in
                        (
                            source,
                            [
                                CapacityWindow.unknown(
                                    reason: .neverSampled,
                                    source: source,
                                    scope: .weekly,
                                    observedAt: now,
                                    sourceTier: .tuiProbe
                                ),
                            ]
                        )
                    }
                ),
                now: now
            )
        }

        let executor = probeExecutor ?? LiveCapacityProbeExecutor()
        let group = DispatchGroup()
        final class ProbeResults: @unchecked Sendable {
            private let lock = NSLock()
            private var map: [String: [CapacityWindow]] = [:]
            func set(_ source: String, _ windows: [CapacityWindow]) {
                lock.lock(); map[source] = windows; lock.unlock()
            }
            func snapshot() -> [String: [CapacityWindow]] {
                lock.lock(); defer { lock.unlock() }
                return map
            }
        }
        let probeResults = ProbeResults()

        let effectiveTimeouts = sourcesToProbe.map { source -> TimeInterval in
            if probeTimeout == CapacityProbe.defaultTimeout {
                return CapacityProbe.timeout(for: source)
            }
            return probeTimeout
        }
        let maxProbeTimeout = effectiveTimeouts.max() ?? probeTimeout

        for source in benchSourceOrder where sourcesToProbe.contains(source) {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let seatTimeout = probeTimeout == CapacityProbe.defaultTimeout
                    ? CapacityProbe.timeout(for: source)
                    : probeTimeout
                let windows = executor.execute(
                    CapacityProbeRequest(source: source, now: now, timeout: seatTimeout)
                )
                let safe: [CapacityWindow]
                if windows.isEmpty {
                    safe = [
                        CapacityProbe.unknown(
                            source: source,
                            reason: .parserFailed(observedAt: now),
                            now: now
                        ),
                    ]
                } else {
                    safe = windows.map { window in
                        if window.unknownReason == .vendorExposesNothing {
                            return CapacityProbe.unknown(
                                source: source,
                                reason: .parserFailed(observedAt: now),
                                now: now
                            )
                        }
                        return window
                    }
                }
                probeResults.set(source, safe)
            }
        }

        let margin = max(2.0, maxProbeTimeout * 0.1)
        let groupTimeout = maxProbeTimeout + margin
        let waitResult = group.wait(timeout: .now() + groupTimeout)
        if waitResult == .timedOut {
            CapacityProbe.terminateAllActiveProbes()
            _ = group.wait(timeout: .now() + 1.0)
        }

        var bySource: [String: [CapacityWindow]] = [:]
        let probed = probeResults.snapshot()
        for source in benchSourceOrder {
            if sourcesToProbe.contains(source) {
                if let windows = probed[source] {
                    bySource[source] = windows
                } else {
                    bySource[source] = [
                        CapacityProbe.unknown(
                            source: source,
                            reason: .probeTimeout(observedAt: now),
                            now: now
                        ),
                    ]
                }
            } else {
                bySource[source] = [
                    CapacityWindow.unknown(
                        reason: .neverSampled,
                        source: source,
                        scope: .weekly,
                        observedAt: now,
                        sourceTier: .tuiProbe
                    ),
                ]
            }
        }
        return orderedBenchWindows(bySource, now: now)
    }

    private static func orderedBenchWindows(
        _ bySource: [String: [CapacityWindow]],
        now: Date
    ) -> [CapacityWindow] {
        var result: [CapacityWindow] = []
        for source in benchSourceOrder {
            if let windows = bySource[source], !windows.isEmpty {
                result.append(contentsOf: windows)
            } else {
                result.append(
                    CapacityWindow.unknown(
                        reason: .neverSampled,
                        source: source,
                        scope: .weekly,
                        observedAt: now,
                        sourceTier: .tuiProbe
                    )
                )
            }
        }
        return result
    }
}
