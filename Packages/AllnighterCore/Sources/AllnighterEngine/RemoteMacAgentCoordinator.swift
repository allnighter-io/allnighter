import Foundation
import AllnighterCore

public protocol RemoteMacAgentDraining: Sendable {
    func drainOnce() async throws -> RemoteMacAgentDrainResult
}

extension RemoteMacAgent: RemoteMacAgentDraining {}

public protocol RemoteMacAgentSleeping: Sendable {
    func sleep(for interval: TimeInterval) async throws
}

public struct DefaultRemoteMacAgentSleeper: RemoteMacAgentSleeping {
    public init() {}

    public func sleep(for interval: TimeInterval) async throws {
        guard interval > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}

public struct RemoteMacAgentPollPolicy: Equatable, Sendable {
    public static let minimumDelay: TimeInterval = 0.001

    public var pollInterval: TimeInterval
    public var initialFailureBackoff: TimeInterval
    public var maximumFailureBackoff: TimeInterval
    public var backoffMultiplier: Double

    public init(
        pollInterval: TimeInterval = 5,
        initialFailureBackoff: TimeInterval = 1,
        maximumFailureBackoff: TimeInterval = 60,
        backoffMultiplier: Double = 2
    ) {
        let initialFailureBackoff = Self.normalizedDelay(initialFailureBackoff, fallback: 1)
        let maximumFailureBackoff = Self.normalizedDelay(maximumFailureBackoff, fallback: 60)
        self.pollInterval = Self.normalizedDelay(pollInterval, fallback: 5)
        self.initialFailureBackoff = initialFailureBackoff
        self.maximumFailureBackoff = max(initialFailureBackoff, maximumFailureBackoff)
        self.backoffMultiplier = backoffMultiplier.isFinite ? max(1, backoffMultiplier) : 2
    }

    private static func normalizedDelay(_ delay: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        guard delay.isFinite else { return fallback }
        return max(minimumDelay, delay)
    }
}

public enum RemoteMacAgentPollOutcome: Equatable, Sendable {
    case drained(processedCommandCount: Int, syncedTrustedDeviceCount: Int)
    case failed(errorType: String)
}

public struct RemoteMacAgentPollEvent: Equatable, Sendable {
    public var attempt: Int
    public var outcome: RemoteMacAgentPollOutcome
    public var nextDelay: TimeInterval
    public var at: Date

    public init(
        attempt: Int,
        outcome: RemoteMacAgentPollOutcome,
        nextDelay: TimeInterval,
        at: Date
    ) {
        self.attempt = attempt
        self.outcome = outcome
        self.nextDelay = nextDelay
        self.at = at
    }
}

public protocol RemoteMacAgentCoordinating: Sendable {
    func run(isCancelled: @escaping @Sendable () -> Bool) async
}

/// Headless poll backstop for the outbound remote Mac agent. Realtime can wake the
/// same drain path later; this loop is the at-least-once delivery guarantee.
public final class RemoteMacAgentCoordinator: RemoteMacAgentCoordinating, @unchecked Sendable {
    private let agent: any RemoteMacAgentDraining
    private let policy: RemoteMacAgentPollPolicy
    private let sleeper: any RemoteMacAgentSleeping
    private let now: @Sendable () -> Date
    private let observe: (@Sendable (RemoteMacAgentPollEvent) -> Void)?

    public init(
        agent: any RemoteMacAgentDraining,
        policy: RemoteMacAgentPollPolicy = RemoteMacAgentPollPolicy(),
        sleeper: any RemoteMacAgentSleeping = DefaultRemoteMacAgentSleeper(),
        now: @escaping @Sendable () -> Date = Date.init,
        observe: (@Sendable (RemoteMacAgentPollEvent) -> Void)? = nil
    ) {
        self.agent = agent
        self.policy = policy
        self.sleeper = sleeper
        self.now = now
        self.observe = observe
    }

    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        var attempt = 0
        var failureBackoff = policy.initialFailureBackoff

        while !isCancelled() {
            attempt += 1
            let delay: TimeInterval
            let outcome: RemoteMacAgentPollOutcome

            do {
                let result = try await agent.drainOnce()
                delay = policy.pollInterval
                failureBackoff = policy.initialFailureBackoff
                outcome = .drained(
                    processedCommandCount: result.processedCommandCount,
                    syncedTrustedDeviceCount: result.syncedTrustedDeviceCount
                )
            } catch {
                delay = failureBackoff
                failureBackoff = min(policy.maximumFailureBackoff, failureBackoff * policy.backoffMultiplier)
                outcome = .failed(errorType: String(describing: type(of: error)))
            }

            observe?(RemoteMacAgentPollEvent(attempt: attempt, outcome: outcome, nextDelay: delay, at: now()))
            do {
                try await sleeper.sleep(for: delay)
            } catch {
                break
            }
        }
    }
}
