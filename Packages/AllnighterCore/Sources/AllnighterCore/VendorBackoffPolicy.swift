import Foundation

/// Pure RLC-S01 policy helpers. Runtime parking and coordinator wake claims belong to S02.
public enum VendorBackoffPolicy {
    public static let minimumPadSeconds: TimeInterval = 2 * 60
    public static let minimumJitterSeconds: TimeInterval = 1 * 60
    public static let maximumJitterSeconds: TimeInterval = 5 * 60
    /// A wake is a real resume probe, not a free ping. Unknown reset windows back
    /// off from five minutes to at most one hour and always stop at this bound.
    public static let unknownResetBaseDelaySeconds: TimeInterval = 5 * 60
    public static let unknownResetMaximumDelaySeconds: TimeInterval = 60 * 60
    public static let maximumAttempts = 5
    public static let probeTimeoutSeconds = 30
    public static let wakeLeaseSeconds: TimeInterval = 2 * 60
    /// Long enough for monthly quota windows while rejecting corrupt/distant-future clocks.
    public static let maximumResetDistanceSeconds: TimeInterval = 366 * 24 * 60 * 60

    /// Park only a sourced account limit. Structured account-limit events may take
    /// the S02 unknown-reset path; message fallback requires a vendor-stated reset
    /// instant or Retry-After duration. Busy, cooldown, unknown, and user blockers
    /// remain in their existing retry/reseat paths.
    public static func shouldPark(_ observation: CapacityObservation) -> Bool {
        guard observation.kind == .accountRateLimit else { return false }
        switch observation.sourceConfidence {
        case .structured:
            return true
        case .messageFallback:
            return observation.observedResetAt != nil || observation.retryAfterSeconds != nil
        case .localPolicy, .unknown:
            return false
        }
    }

    /// Computes a conservative UTC instant from vendor-sourced reset truth.
    ///
    /// `Date` is already an absolute UTC instant. Missing, past, non-finite, or
    /// implausibly distant reset facts return nil for S02's unknown-reset path.
    /// The random source is injectable for deterministic tests; its value is
    /// clamped to the required one-to-five-minute jitter range.
    public static func computeWakeAfter(
        from observation: CapacityObservation,
        now: Date = Date(),
        jitter: () -> TimeInterval = { Double.random(in: minimumJitterSeconds...maximumJitterSeconds) }
    ) -> Date? {
        let resetAt = observation.observedResetAt
            ?? observation.retryAfterSeconds.map {
                observation.observedAt.addingTimeInterval(TimeInterval($0))
            }
        guard let resetAt else { return nil }

        let distance = resetAt.timeIntervalSince(now)
        guard distance.isFinite, distance > 0, distance <= maximumResetDistanceSeconds else {
            return nil
        }

        let jitterSeconds = min(max(jitter(), minimumJitterSeconds), maximumJitterSeconds)
        guard jitterSeconds.isFinite else { return nil }
        return resetAt.addingTimeInterval(minimumPadSeconds + jitterSeconds)
    }

    /// Local-only cadence for a structured account limit that omitted usable reset
    /// truth. This boundary is never presented as a vendor-stated reset.
    public static func unknownResetWakeAfter(
        attemptNumber: Int,
        observedAt: Date
    ) -> Date {
        let exponent = max(0, min(attemptNumber - 1, 20))
        let delay = min(
            unknownResetBaseDelaySeconds * pow(2, Double(exponent)),
            unknownResetMaximumDelaySeconds
        )
        return observedAt.addingTimeInterval(delay)
    }
}
