import Foundation
import AllnighterCore

/// Durable record of `NotificationCandidate.id`s `alln serve` has already
/// delivered, so a daemon restart never replays an old banner. Deliberately
/// separate from `NotificationPolicy` — that file is Mac-app/user-settings
/// owned, and the daemon never writes it (URN-S01 "policy is read-only from
/// the daemon"). Losing this file costs at most one duplicate banner.
public struct DeliveredNotificationLedger: Codable, Sendable, Equatable {
    public var deliveredIds: Set<String>

    public init(deliveredIds: Set<String> = []) {
        self.deliveredIds = deliveredIds
    }
}

/// Persists `DeliveredNotificationLedger` under `AllnighterPaths.coordinator`,
/// next to `coordinator.json` (`ServeDaemonStore`'s file).
public struct DeliveredNotificationLedgerStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterPaths.coordinator.appendingPathComponent("delivered_notifications.json")
    }

    public func load() -> DeliveredNotificationLedger {
        guard let data = try? Data(contentsOf: fileURL),
              let ledger = try? CoreJSON.decode(DeliveredNotificationLedger.self, from: data) else {
            return DeliveredNotificationLedger()
        }
        return ledger
    }

    @discardableResult
    public func save(_ ledger: DeliveredNotificationLedger) -> URL? {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try CoreJSON.encode(ledger).write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }
}

/// Resident loop for `alln serve`: posts local OS notifications for
/// relay/pilot/team-run state so CLI-only work notifies the founder with the
/// Mac app closed (URN-S01,
/// `docs/phases/Unattended_Round_Notification.md`). Strictly
/// read-then-shell-out — it reads `ThreadStore`/`RunStore`/
/// `NotificationPolicyStore` and spawns `osascript`. It never touches
/// `RunService`, `AsyncTeamService`, or `RunWriteLockRegistry`: no run
/// mutation, no write-lock interaction, ever (see the packet's §Inference
/// bans).
public struct NotificationScheduler: Sendable {
    public var threadStore: ThreadStore
    public var runStore: RunStore
    public var policyStore: NotificationPolicyStore
    public var ledgerStore: DeliveredNotificationLedgerStore
    public var commandRunner: CommandRunner
    public var models: [Model]
    public var registry: DriverRegistry
    public var now: @Sendable () -> Date
    public var sleeper: any PendingWakeSleeper
    public var pollInterval: TimeInterval

    public init(
        threadStore: ThreadStore = ThreadStore(),
        runStore: RunStore = RunStore(),
        policyStore: NotificationPolicyStore = NotificationPolicyStore(),
        ledgerStore: DeliveredNotificationLedgerStore = DeliveredNotificationLedgerStore(),
        commandRunner: CommandRunner = SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()),
        models: [Model],
        registry: DriverRegistry,
        now: @escaping @Sendable () -> Date = Date.init,
        sleeper: any PendingWakeSleeper = DefaultPendingWakeSleeper(),
        pollInterval: TimeInterval = 10
    ) {
        self.threadStore = threadStore
        self.runStore = runStore
        self.policyStore = policyStore
        self.ledgerStore = ledgerStore
        self.commandRunner = commandRunner
        self.models = models
        self.registry = registry
        self.now = now
        self.sleeper = sleeper
        self.pollInterval = pollInterval
    }

    /// Runs until `isCancelled` returns true. The very first tick's `before`
    /// snapshot is `nil`, which `NotificationCandidateDetection.candidates`/
    /// `.runCandidates` already treat as "cold start, emit nothing" — so a
    /// fresh daemon (including one that just restarted) never floods stale
    /// transitions.
    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        var previousThreads: [String: ThreadNotificationSnapshot]?
        var previousRuns: [String: RunNotificationSnapshot]?
        var ledger = ledgerStore.load()

        while !isCancelled() {
            let tickTime = now()
            let result = await tick(
                previousThreads: previousThreads,
                previousRuns: previousRuns,
                ledger: ledger,
                tickTime: tickTime
            )
            previousThreads = result.threads
            previousRuns = result.runs
            ledger = result.ledger

            guard !isCancelled() else { break }
            do {
                try await sleeper.sleep(until: now().addingTimeInterval(pollInterval), jitterSeconds: 0)
            } catch {
                break
            }
        }
    }

    /// One poll cycle: loads current store state, diffs it against the
    /// previous tick's snapshots, and delivers any new, not-yet-delivered,
    /// policy-eligible candidate. Returns the new snapshots (for the next
    /// tick's diff) and the updated ledger. Exposed at module visibility
    /// (not private) so tests can drive individual ticks deterministically
    /// instead of racing the sleep loop.
    func tick(
        previousThreads: [String: ThreadNotificationSnapshot]?,
        previousRuns: [String: RunNotificationSnapshot]?,
        ledger: DeliveredNotificationLedger,
        tickTime: Date
    ) async -> (threads: [String: ThreadNotificationSnapshot], runs: [String: RunNotificationSnapshot], ledger: DeliveredNotificationLedger) {
        let threads = threadStore.list()
        let runs = runStore.list()
        let runsById = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })

        let threadSnapshots = NotificationCandidateDetection.snapshots(from: threads)
        let runSnapshots = NotificationCandidateDetection.runSnapshots(from: threads, runsById: runsById)

        var candidates = NotificationCandidateDetection.candidates(
            before: previousThreads, after: threadSnapshots, now: tickTime
        )
        candidates += NotificationCandidateDetection.runCandidates(
            before: previousRuns, after: runSnapshots, now: tickTime
        )

        var updatedLedger = ledger
        if !candidates.isEmpty {
            // Read-only load — the daemon never calls `NotificationPolicyStore.save`
            // or `NotificationDeliveryFilter.recordDelivery`. That file is Mac-app/
            // user-settings owned; our own ledger is the dedupe source of truth.
            let policy = policyStore.load()
            let deliverable = Self.deliverableCandidates(
                candidates, ledger: updatedLedger, policy: policy, now: tickTime
            )
            for candidate in deliverable {
                await deliver(candidate: candidate)
                updatedLedger.deliveredIds.insert(candidate.id)
                ledgerStore.save(updatedLedger)
            }
        }

        return (threadSnapshots, runSnapshots, updatedLedger)
    }

    /// Pure filter: a candidate is deliverable when it has not already been
    /// delivered (our ledger) AND `NotificationDeliveryFilter.shouldDeliver`
    /// agrees (policy enabled, thread not muted, event enabled, not quiet
    /// hours, debounce). Delegates entirely to the existing filter rather
    /// than re-implementing any of its rules.
    static func deliverableCandidates(
        _ candidates: [NotificationCandidate],
        ledger: DeliveredNotificationLedger,
        policy: NotificationPolicy,
        now: Date
    ) -> [NotificationCandidate] {
        candidates.filter { candidate in
            !ledger.deliveredIds.contains(candidate.id)
                && NotificationDeliveryFilter.shouldDeliver(candidate: candidate, policy: policy, now: now)
        }
    }

    private func deliver(candidate: NotificationCandidate) async {
        let workerName = candidate.workerId.map(driverDisplayName(for:))
        let title = NotificationCopy.title(candidate: candidate, workerDisplayName: workerName)
        let body = NotificationCopy.body(candidate: candidate)

        #if canImport(Darwin)
        let script = "display notification \"\(Self.appleScriptEscaped(body))\" with title \"\(Self.appleScriptEscaped(title))\""
        let result = await commandRunner.run(
            command: "osascript",
            args: ["-e", script],
            stdin: nil,
            env: [:],
            workingDirectory: nil,
            timeout: .seconds(5)
        )
        logDelivery(candidate: candidate, result: result)
        #else
        logNonDarwinSkip(candidate: candidate)
        #endif
    }

    private func driverDisplayName(for workerId: String) -> String {
        guard let model = models.first(where: { $0.id == workerId }) else { return workerId }
        return registry.manifest(for: model)?.displayName ?? model.driverId
    }

    /// Escapes an arbitrary string (thread titles are user-controlled text)
    /// for safe embedding inside a double-quoted AppleScript string literal.
    /// Backslashes and double quotes are the two characters that would
    /// otherwise break out of the literal.
    static func appleScriptEscaped(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            default: out.append(ch)
            }
        }
        return out
    }

    // Every delivery attempt (success or failure) writes one stderr line —
    // a failed `osascript` (e.g. Script Editor notification permission
    // denied) is logged, never swallowed, and never stops the loop.
    private func logDelivery(candidate: NotificationCandidate, result: CommandResult) {
        let status: String
        if let launchError = result.launchError {
            status = "launch-error: \(launchError)"
        } else if result.exitCode == 0 {
            status = "ok"
        } else {
            status = "failed exit=\(result.exitCode.map(String.init) ?? "nil")"
        }
        writeStderr("[NotificationScheduler] delivery candidate=\(candidate.id) event=\(candidate.event.rawValue) \(status)")
    }

    private func logNonDarwinSkip(candidate: NotificationCandidate) {
        writeStderr("[NotificationScheduler] skipped candidate=\(candidate.id) reason=non-darwin-platform")
    }

    private func writeStderr(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
