import Foundation

public struct WakeSafeWaiter: PendingWakeSleeper, @unchecked Sendable {
    public let maxNapSeconds: TimeInterval
    public let now: @Sendable () -> Date
    public let performSleep: @Sendable (TimeInterval) async throws -> Void
    private let _storage: Storage

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var lastOvershoot: TimeInterval = 0
    }

    public var lastOvershoot: TimeInterval {
        _storage.lock.withLock { _storage.lastOvershoot }
    }

    public init(
        maxNapSeconds: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init,
        performSleep: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    ) {
        self.maxNapSeconds = maxNapSeconds
        self.now = now
        self.performSleep = performSleep
        self._storage = Storage()
    }

    public func sleep(until deadline: Date, jitterSeconds: TimeInterval) async throws {
        let jitter = jitterSeconds > 0 ? TimeInterval(Int.random(in: 0...Int(jitterSeconds))) : 0
        let targetDeadline = deadline.addingTimeInterval(jitter)

        while true {
            let currentNow = now()
            if currentNow >= targetDeadline {
                let overshoot = currentNow.timeIntervalSince(targetDeadline)
                _storage.lock.withLock { _storage.lastOvershoot = overshoot }
                return
            }
            let remaining = targetDeadline.timeIntervalSince(currentNow)
            let napDuration = min(remaining, maxNapSeconds)
            try await performSleep(napDuration)
        }
    }
}
