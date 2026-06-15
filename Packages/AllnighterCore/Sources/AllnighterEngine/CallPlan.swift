import Foundation
import AllnighterCore

/// A previewed cost estimate for a run, shown before it commits so cost is never
/// silent (`00` §9). In Phase 06 it covers the panel seats + synthesis calls; RB1
/// extends it across the full workflow chain. Estimates are labeled estimates.
public struct CallPlan: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var stage: String          // "panel" | "analysis" | "plan" | lens/stage id
        public var seatId: String?
        public var workerId: String?
        public var willReuse: Bool
        public init(stage: String, seatId: String? = nil, workerId: String? = nil, willReuse: Bool = false) {
            self.stage = stage
            self.seatId = seatId
            self.workerId = workerId
            self.willReuse = willReuse
        }
    }

    public var entries: [Entry]
    public var estimatedCalls: Int
    public var estimatedSeconds: Int
    public var estimateNote: String

    public init(entries: [Entry], estimatedCalls: Int, estimatedSeconds: Int, estimateNote: String) {
        self.entries = entries
        self.estimatedCalls = estimatedCalls
        self.estimatedSeconds = estimatedSeconds
        self.estimateNote = estimateNote
    }

    /// Rough quota risk bucket from the fresh-call count.
    public var quotaRisk: String {
        switch estimatedCalls {
        case ..<4: return "low"
        case 4..<9: return "medium"
        default: return "high"
        }
    }
}

/// Builds a `CallPlan` for a panel preset. Per-worker latency is the median of
/// prior `durationMs` from history when available, else a static default.
public struct CallPlanEstimator: Sendable {
    private let defaultSeatSeconds: Int

    public init(defaultSeatSeconds: Int = 30) {
        self.defaultSeatSeconds = defaultSeatSeconds
    }

    /// `latencyByWorker` is a precomputed median seconds per worker id (from
    /// local run history). Seats run in parallel, so wall time ≈ slowest seat +
    /// the serial synthesis calls.
    public func plan(for preset: PanelPreset, latencyByWorker: [String: Int] = [:]) -> CallPlan {
        let seats = preset.seats.expandedSeats()
        var entries: [CallPlan.Entry] = seats.map {
            .init(stage: "panel", seatId: $0.id, workerId: $0.workerId)
        }
        let synthesisCalls = preset.synthesis.analysisDepth == .combined ? 1 : 2
        let judgeId = preset.synthesis.judgeWorkerId
        entries.append(.init(stage: "analysis", workerId: judgeId))
        entries.append(.init(stage: "plan", workerId: judgeId))

        let calls = seats.count + synthesisCalls

        let seatSeconds = seats.map { latencyByWorker[$0.workerId] ?? defaultSeatSeconds }
        let slowestSeat = seatSeconds.max() ?? defaultSeatSeconds
        let judgeSeconds = (judgeId.flatMap { latencyByWorker[$0] }) ?? defaultSeatSeconds
        let estSeconds = slowestSeat + synthesisCalls * judgeSeconds

        return CallPlan(
            entries: entries,
            estimatedCalls: calls,
            estimatedSeconds: estSeconds,
            estimateNote: "Estimate: \(seats.count) panel + \(synthesisCalls) synthesis call(s); parallel panel, serial synthesis. Actual time/quota varies."
        )
    }
}
