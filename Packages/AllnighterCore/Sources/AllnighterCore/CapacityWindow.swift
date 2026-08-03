import Foundation

// MARK: - Supporting types

/// Limit-window scope for a capacity sample. Pool/group membership is a
/// separate label (`poolLabel`), not a scope — one CLI can expose several
/// windows (weekly + fiveHour) under one pool name (agy).
public enum CapacityWindowScope: String, Sendable, Equatable, Codable, CaseIterable {
    case weekly
    case fiveHour
    case monthly
    case session
    case planClass
}

/// How precisely `resetAt` is known. Cursor's bare "Resets Aug 25" is day-only;
/// relative durations (agy/kimi) resolve to the minute; ISO8601/unix are exact.
/// Never store a fabricated time and mark it exact.
public enum CapacityResetPrecision: String, Sendable, Equatable, Codable, CaseIterable {
    case exact
    case minute
    case day
}

/// Acquisition ladder tier that produced the sample (product §Acquisition ladder).
public enum CapacityAcquisitionTier: Int, Sendable, Equatable, Codable, CaseIterable {
    /// Vendor session/rollout log already on disk (Codex, Grok).
    case onDisk = 1
    /// Structured stream piggyback on a real run.
    case streamPiggyback = 2
    /// PTY one-shot into the vendor usage/status TUI (Claude, agy, kimi, cursor).
    case tuiProbe = 3
    /// Reactive failure classification (existing 429 path).
    case failureClassification = 4
}

/// Routing bucket. Decisions consume the bucket, never the raw percentage —
/// a parser can be wrong about the number while still right about the order.
public enum CapacityBucket: String, Sendable, Equatable, Codable, CaseIterable {
    case fat
    case thin
    case empty
    case unknown
}

/// Why a sample is missing. Never a bare nil, never zero-filled into 0%.
public enum CapacityUnknownReason: Sendable, Equatable, Codable {
    /// Vendor has no usage surface for this seat.
    case vendorExposesNothing
    /// A surface exists but the parser could not read it; `observedAt` is when we tried.
    case parserFailed(observedAt: Date)
    /// We have not attempted acquisition yet (and have no durable last-known).
    case neverSampled
    /// Vendor binary missing / spawn failed (CAP-HF-claude).
    case spawnFailed(observedAt: Date)
    /// PTY probe hit the wall-clock budget before a usable screen.
    case probeTimeout(observedAt: Date)
    /// Probe ran but capture was empty (no usage pane text).
    case emptyCapture(observedAt: Date)
    /// Sample succeeded but aged past the resident paint gate (CWB-S01a);
    /// `observedAt` is the original sample time so age labels stay honest.
    case expired(observedAt: Date)
}

/// Paid spend that is **not** a percentage — cursor dollars, grok on-demand
/// integer units. Never coerce money into a fake used-percent.
public struct CapacityPaidAmount: Sendable, Equatable, Codable {
    /// Amount spent so far.
    public let used: Double
    /// Hard cap when the vendor prints one.
    public let cap: Double?
    /// Remaining when known (vendor-printed or cap − used).
    public let remaining: Double?
    /// `"$"` for dollars; `nil` for dimensionless vendor units (grok `{"val": N}`).
    public let unit: String?

    public init(used: Double, cap: Double? = nil, remaining: Double? = nil, unit: String? = nil) {
        self.used = used
        self.cap = cap
        self.remaining = remaining
        self.unit = unit
    }
}

// MARK: - CapacityWindow

/// One normalized capacity window every driver extractor can emit.
///
/// Pure surface: no `Date()`, no file IO, no environment reads. Callers pass
/// every clock value in. Polarity is normalized at construction via named
/// `init(used:)` / `init(remaining:)` so no call site can pass the wrong
/// polarity positionally — both fields are always derived together.
///
/// Conversion surfaces: `GrokWeeklyCapacity.asCapacityWindow()`,
/// `AgyPoolCapacity.asCapacityWindows()`, `KimiCapacityWindow.asCapacityWindow()`,
/// `CursorCapacitySnapshot.asCapacityWindows()` (CAP-S02). Fields sized so each
/// extractor maps without loss: agy pools + remaining polarity, cursor
/// day-precision reset + dollar spend, grok on-demand/prepaid, kimi used polarity.
public struct CapacityWindow: Sendable, Equatable, Codable {

    // MARK: Thresholds (named — never magic numbers at the call site)

    /// Remaining at or above this is `fat`. Aligns with the worker pre-dispatch
    /// floor scale (~20%) from the capacity product packet.
    public static let fatRemainingThreshold: Double = 20.0

    /// Remaining at or below this is `empty`.
    public static let emptyRemainingThreshold: Double = 0.0

    // MARK: Fields

    /// Driver/source id — `grok`, `agy`, `kimi`, `cursor_agent`, `codex`…
    public let source: String
    public let scope: CapacityWindowScope
    /// Percentage used (0…100+). Nil only when `unknownReason` is set.
    public let usedPercent: Double?
    /// Percentage remaining (0…100). Nil only when `unknownReason` is set.
    public let remainingPercent: Double?
    /// Absolute reset instant when known.
    public let resetAt: Date?
    public let resetPrecision: CapacityResetPrecision
    /// Wall clock of the sample (or of the failed parse attempt).
    public let observedAt: Date
    public let sourceTier: CapacityAcquisitionTier
    /// Vendor pool/group label when models share a limit (e.g. agy "GEMINI MODELS").
    public let poolLabel: String?
    /// Plan/subscription tier string when the vendor prints one (e.g. "X Premium+", "Ultra").
    public let planTier: String?
    /// Set only for unknown samples — never alongside a zero-filled percentage.
    public let unknownReason: CapacityUnknownReason?
    /// On-demand paid spend (cursor dollars / grok on-demand units).
    public let onDemand: CapacityPaidAmount?
    /// Prepaid balance in vendor units (grok). Later slices must not auto-spend this.
    public let prepaidBalance: Double?

    // MARK: Named constructors (polarity-safe)

    /// Build from a **used** percentage (codex / grok / kimi / cursor polarity).
    /// Derives `remainingPercent = max(0, 100 − used)`.
    public init(
        used usedPercent: Double,
        source: String,
        scope: CapacityWindowScope,
        resetAt: Date?,
        resetPrecision: CapacityResetPrecision,
        observedAt: Date,
        sourceTier: CapacityAcquisitionTier,
        poolLabel: String? = nil,
        planTier: String? = nil,
        onDemand: CapacityPaidAmount? = nil,
        prepaidBalance: Double? = nil
    ) {
        self.source = source
        self.scope = scope
        self.usedPercent = usedPercent
        self.remainingPercent = max(0.0, 100.0 - usedPercent)
        self.resetAt = resetAt
        self.resetPrecision = resetPrecision
        self.observedAt = observedAt
        self.sourceTier = sourceTier
        self.poolLabel = poolLabel
        self.planTier = planTier
        self.unknownReason = nil
        self.onDemand = onDemand
        self.prepaidBalance = prepaidBalance
    }

    /// Build from a **remaining** percentage (agy polarity).
    /// Derives `usedPercent = max(0, 100 − remaining)`.
    public init(
        remaining remainingPercent: Double,
        source: String,
        scope: CapacityWindowScope,
        resetAt: Date?,
        resetPrecision: CapacityResetPrecision,
        observedAt: Date,
        sourceTier: CapacityAcquisitionTier,
        poolLabel: String? = nil,
        planTier: String? = nil,
        onDemand: CapacityPaidAmount? = nil,
        prepaidBalance: Double? = nil
    ) {
        self.source = source
        self.scope = scope
        self.remainingPercent = remainingPercent
        self.usedPercent = max(0.0, 100.0 - remainingPercent)
        self.resetAt = resetAt
        self.resetPrecision = resetPrecision
        self.observedAt = observedAt
        self.sourceTier = sourceTier
        self.poolLabel = poolLabel
        self.planTier = planTier
        self.unknownReason = nil
        self.onDemand = onDemand
        self.prepaidBalance = prepaidBalance
    }

    /// Unknown sample — percentages stay nil so missing can never look like 0%.
    public static func unknown(
        reason: CapacityUnknownReason,
        source: String,
        scope: CapacityWindowScope,
        observedAt: Date,
        sourceTier: CapacityAcquisitionTier,
        resetPrecision: CapacityResetPrecision = .exact,
        poolLabel: String? = nil,
        planTier: String? = nil
    ) -> CapacityWindow {
        CapacityWindow(
            source: source,
            scope: scope,
            usedPercent: nil,
            remainingPercent: nil,
            resetAt: nil,
            resetPrecision: resetPrecision,
            observedAt: observedAt,
            sourceTier: sourceTier,
            poolLabel: poolLabel,
            planTier: planTier,
            unknownReason: reason,
            onDemand: nil,
            prepaidBalance: nil
        )
    }

    /// Private full-field init used by `unknown` (and Codable synthesis path is separate).
    private init(
        source: String,
        scope: CapacityWindowScope,
        usedPercent: Double?,
        remainingPercent: Double?,
        resetAt: Date?,
        resetPrecision: CapacityResetPrecision,
        observedAt: Date,
        sourceTier: CapacityAcquisitionTier,
        poolLabel: String?,
        planTier: String?,
        unknownReason: CapacityUnknownReason?,
        onDemand: CapacityPaidAmount?,
        prepaidBalance: Double?
    ) {
        self.source = source
        self.scope = scope
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
        self.resetPrecision = resetPrecision
        self.observedAt = observedAt
        self.sourceTier = sourceTier
        self.poolLabel = poolLabel
        self.planTier = planTier
        self.unknownReason = unknownReason
        self.onDemand = onDemand
        self.prepaidBalance = prepaidBalance
    }

    // MARK: Bucket

    /// Bucket for routing. Unknown reasons and missing percentages are `unknown`;
    /// never confusable with `empty` (0% remaining).
    public var bucket: CapacityBucket {
        Self.bucket(remainingPercent: remainingPercent, unknownReason: unknownReason)
    }

    /// Pure classifier — thresholds are the named constants above.
    public static func bucket(
        remainingPercent: Double?,
        unknownReason: CapacityUnknownReason?
    ) -> CapacityBucket {
        if unknownReason != nil { return .unknown }
        guard let remaining = remainingPercent else { return .unknown }
        if remaining <= emptyRemainingThreshold { return .empty }
        if remaining < fatRemainingThreshold { return .thin }
        return .fat
    }

    // MARK: Anchored decrement

    /// Strict upper bound on remaining capacity:
    /// `sample.remaining − (our own observed burn since sample.observedAt)`.
    ///
    /// Monotone (never above the observation), clamps at zero, equals the
    /// observation at zero burn. Not a projection — no forecast of future usage.
    public static func remainingCeiling(
        remainingObserved: Double,
        burnPercentSinceObservation: Double
    ) -> Double {
        let burn = max(0.0, burnPercentSinceObservation)
        return max(0.0, remainingObserved - burn)
    }

    /// Anchored ceiling for this window's remaining, or nil when unknown.
    public func remainingCeiling(burnPercentSinceObservation: Double) -> Double? {
        guard let remaining = remainingPercent else { return nil }
        return Self.remainingCeiling(
            remainingObserved: remaining,
            burnPercentSinceObservation: burnPercentSinceObservation
        )
    }
}
