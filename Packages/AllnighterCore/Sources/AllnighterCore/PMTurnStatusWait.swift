import Foundation

/// Shared bounded waiter for relay-backed PM Turn status commands. It models PM
/// boundaries rather than run lifecycle states: a parked relay needs PM input,
/// while a terminal relay will not progress further on its own.
public enum PMTurnStatusWait {
    public enum Target: String, Sendable, Equatable {
        case parked
        case terminal

        public func matches(_ status: LoopState.Status) -> Bool {
            switch self {
            case .parked: status == .awaitingPM || status == .escalated
            case .terminal: status == .done || status == .stopped
            }
        }

        /// A non-matching PM boundary cannot progress without another PM action.
        public func isTerminalMismatch(_ status: LoopState.Status) -> Bool {
            switch self {
            case .parked: status == .done || status == .stopped
            case .terminal: status == .awaitingPM || status == .escalated
            }
        }
    }

    public enum Outcome: String, Sendable, Equatable {
        case matched
        case timedOut
        case terminalMismatch
    }

    public struct Result: Sendable, Equatable {
        public let status: LoopState.Status
        public let outcome: Outcome

        public init(status: LoopState.Status, outcome: Outcome) {
            self.status = status
            self.outcome = outcome
        }
    }

    public static let minimumPollInterval: TimeInterval = 0.05
    public static let maximumPollInterval: TimeInterval = 5

    /// Uses the same 50ms–5s cadence bounds as team status. `now` and `sleep`
    /// are injected so outcome tests do not rely on wall-clock sleeps.
    public static func wait(
        target: Target,
        timeout: TimeInterval,
        pollInterval: TimeInterval = minimumPollInterval,
        readStatus: () -> LoopState.Status,
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = Thread.sleep
    ) -> Result {
        let deadline = now().addingTimeInterval(timeout)
        let delay = min(max(minimumPollInterval, pollInterval), maximumPollInterval)

        while true {
            let status = readStatus()
            if target.matches(status) { return Result(status: status, outcome: .matched) }
            if target.isTerminalMismatch(status) { return Result(status: status, outcome: .terminalMismatch) }
            if now() >= deadline { return Result(status: status, outcome: .timedOut) }
            sleep(delay)
        }
    }
}
