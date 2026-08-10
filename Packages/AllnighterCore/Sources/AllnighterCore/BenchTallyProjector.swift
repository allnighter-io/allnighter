import Foundation
import AgentOSCLI

/// Single owner of bench readiness tallies for CLI and Mac chrome (FCS-S01).
///
/// Never invents a ready/total ratio when nothing has been measured: callers
/// read `headline` and the bucket counts. `.neverScanned` carries no ratio by
/// construction — the type does not expose one.
public struct BenchTally: Equatable, Sendable {
    public enum Headline: String, Equatable, Sendable {
        /// No headless CLI manifests loaded (broken bundle / empty registry).
        case configurationMissing
        /// Supported drivers exist, but no probe records yet.
        case neverScanned
        /// Every supported (non-parked) driver is smoke-ready.
        case allReady
        /// At least one measurement exists and none are smoke-ready.
        case noneReady
        /// Some ready, some not.
        case partial
    }

    /// Headless CLI manifests minus parked — a fact about the product catalog.
    public var supported: Int
    /// Supported drivers that have any probe record (observation happened).
    public var measured: Int
    /// Smoke-ready records (`.isSmokeReady`), minus parked.
    public var ready: Int
    /// Assertable needs-a-step statuses (sign-in, path, probe failed, rate limit).
    public var needsStep: Int
    /// Explicit `.notInstalled` records.
    public var notInstalled: Int
    /// Absent record, or a negative that freshness says must not be asserted,
    /// or installed-but-not-smoked.
    public var needsCheck: Int
    public var headline: Headline

    public init(
        supported: Int,
        measured: Int,
        ready: Int,
        needsStep: Int,
        notInstalled: Int,
        needsCheck: Int,
        headline: Headline
    ) {
        self.supported = supported
        self.measured = measured
        self.ready = ready
        self.needsStep = needsStep
        self.notInstalled = notInstalled
        self.needsCheck = needsCheck
        self.headline = headline
    }
}

/// Pure projector: registry + probe records → one tally both CLI and GUI read.
public enum BenchTallyProjector {
    /// Agent / human next step when the bench has never been scanned.
    public static let detectCommand = "alln detect"

    public static func tally(
        registry: DriverRegistry,
        records: [ToolProbeRecord],
        parked: Set<String> = [],
        now: Date = Date()
    ) -> BenchTally {
        let supportedIds = registry.all
            .filter { $0.kind == .headlessCLI && !parked.contains($0.id) }
            .map(\.id)
        let supported = supportedIds.count

        if supported == 0 {
            return BenchTally(
                supported: 0, measured: 0, ready: 0, needsStep: 0,
                notInstalled: 0, needsCheck: 0, headline: .configurationMissing
            )
        }

        let supportedSet = Set(supportedIds)
        let byDriver = latestRecords(byDriver: records, keeping: supportedSet)
        let unassertable = ProbeFreshnessGate.unassertableNegatives(
            Array(byDriver.values), now: now
        )

        var measured = 0
        var ready = 0
        var needsStep = 0
        var notInstalled = 0
        var needsCheck = 0

        for id in supportedIds {
            guard let record = byDriver[id] else {
                needsCheck += 1
                continue
            }
            measured += 1
            switch bucket(record.status, unassertable: unassertable[id]) {
            case .ready: ready += 1
            case .needsStep: needsStep += 1
            case .notInstalled: notInstalled += 1
            case .needsCheck: needsCheck += 1
            }
        }

        let headline: BenchTally.Headline
        if measured == 0 {
            headline = .neverScanned
        } else if ready == supported {
            headline = .allReady
        } else if ready == 0 {
            headline = .noneReady
        } else {
            headline = .partial
        }

        return BenchTally(
            supported: supported,
            measured: measured,
            ready: ready,
            needsStep: needsStep,
            notInstalled: notInstalled,
            needsCheck: needsCheck,
            headline: headline
        )
    }

    // MARK: - Internals

    private enum Bucket {
        case ready, needsStep, notInstalled, needsCheck
    }

    private static func bucket(
        _ status: ModelSetupStatus,
        unassertable: ProbeFreshnessGate.UnassertedReason?
    ) -> Bucket {
        if status.isSmokeReady { return .ready }
        if let unassertable {
            _ = unassertable
            return .needsCheck
        }
        switch status {
        case .notInstalled:
            return .notInstalled
        case .installedNotSignedIn, .shimmedNeedsConfirm, .probeFailed, .rateLimited:
            return .needsStep
        case .installedNotProbed, .ready:
            return .needsCheck
        }
    }

    /// One record per driverId — latest `lastProbeAt` wins. Unknown / non-supported
    /// driver ids are dropped.
    private static func latestRecords(
        byDriver records: [ToolProbeRecord],
        keeping supported: Set<String>
    ) -> [String: ToolProbeRecord] {
        var out: [String: ToolProbeRecord] = [:]
        for record in records where supported.contains(record.driverId) {
            if let prior = out[record.driverId] {
                if record.lastProbeAt >= prior.lastProbeAt {
                    out[record.driverId] = record
                }
            } else {
                out[record.driverId] = record
            }
        }
        return out
    }
}
