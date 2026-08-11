import Foundation
import AllnighterCore

/// `ServeStatusJSON` v2 — §5.2 of `docs/phases/Alln_Serve_Hotfixes.md`.
///
/// Pure status shape + resolver. Inputs are already-gathered observations;
/// this file performs no I/O (`FileManager`, `Process`, `URLSession`, or
/// `Date()`). Timestamps arrive as inputs. Wiring to CLI is ASR-S03f2.
public struct ServeStatusJSON: Equatable, Sendable {

    public var schemaVersion: Int
    public var desiredState: DesiredState
    public var state: State
    public var supervisor: Supervisor
    public var binary: Binary
    public var daemon: Daemon
    public var schedulers: [Scheduler]
    public var recovery: Recovery?

    public enum DesiredState: String, Codable, Sendable, Equatable {
        case enabled
        case disabled
    }

    public enum State: String, Codable, Sendable, Equatable {
        case healthy
        case starting
        case disabled
        case requiresApproval
        case degraded
    }

    public struct Supervisor: Equatable, Sendable {
        public var kind: Kind
        public var label: String
        public var loaded: Bool
        public var authorization: Authorization
        public var pid: Int32?
        public var lastExitCode: Int?

        public enum Kind: String, Codable, Sendable, Equatable {
            case launchAgent
        }

        public enum Authorization: String, Codable, Sendable, Equatable {
            case enabled
            case requiresApproval
            case unknown
        }

        public init(
            kind: Kind = .launchAgent,
            label: String,
            loaded: Bool,
            authorization: Authorization,
            pid: Int32? = nil,
            lastExitCode: Int? = nil
        ) {
            self.kind = kind
            self.label = label
            self.loaded = loaded
            self.authorization = authorization
            self.pid = pid
            self.lastExitCode = lastExitCode
        }
    }

    public struct Binary: Equatable, Sendable {
        public var path: String
        public var expectedGitSha: String?
        public var runningGitSha: String?
        public var expectedCodeIdentity: CanonicalCLIInstall.CodeIdentity?
        public var runningCodeIdentity: CanonicalCLIInstall.CodeIdentity?
        public var matches: Bool

        public init(
            path: String,
            expectedGitSha: String?,
            runningGitSha: String?,
            expectedCodeIdentity: CanonicalCLIInstall.CodeIdentity?,
            runningCodeIdentity: CanonicalCLIInstall.CodeIdentity?,
            matches: Bool
        ) {
            self.path = path
            self.expectedGitSha = expectedGitSha
            self.runningGitSha = runningGitSha
            self.expectedCodeIdentity = expectedCodeIdentity
            self.runningCodeIdentity = runningCodeIdentity
            self.matches = matches
        }
    }

    public struct Daemon: Equatable, Sendable {
        public var daemonId: String?
        public var pid: Int32?
        public var startedAt: Date?
        public var activeHealthRespondedAt: Date?

        public init(
            daemonId: String? = nil,
            pid: Int32? = nil,
            startedAt: Date? = nil,
            activeHealthRespondedAt: Date? = nil
        ) {
            self.daemonId = daemonId
            self.pid = pid
            self.startedAt = startedAt
            self.activeHealthRespondedAt = activeHealthRespondedAt
        }
    }

    public struct Scheduler: Codable, Equatable, Sendable {
        public var id: String
        public var state: ServeRuntimeReceipts.SchedulerState
        public var lastAttemptAt: Date?
        public var lastSuccessAt: Date?
        public var lastError: String?
        public var nextWakeAt: Date?

        public init(
            id: String,
            state: ServeRuntimeReceipts.SchedulerState,
            lastAttemptAt: Date? = nil,
            lastSuccessAt: Date? = nil,
            lastError: String? = nil,
            nextWakeAt: Date? = nil
        ) {
            self.id = id
            self.state = state
            self.lastAttemptAt = lastAttemptAt
            self.lastSuccessAt = lastSuccessAt
            self.lastError = lastError
            self.nextWakeAt = nextWakeAt
        }

        private enum CodingKeys: String, CodingKey {
            case id, state, lastAttemptAt, lastSuccessAt, lastError, nextWakeAt
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            state = try c.decode(ServeRuntimeReceipts.SchedulerState.self, forKey: .state)
            lastAttemptAt = try c.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
            lastSuccessAt = try c.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
            lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
            nextWakeAt = try c.decodeIfPresent(Date.self, forKey: .nextWakeAt)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(state, forKey: .state)
            try c.encode(lastAttemptAt, forKey: .lastAttemptAt)
            try c.encode(lastSuccessAt, forKey: .lastSuccessAt)
            try c.encode(lastError, forKey: .lastError)
            try c.encode(nextWakeAt, forKey: .nextWakeAt)
        }
    }

    /// Non-null for every non-healthy, non-disabled state. Stable reason code
    /// plus one real command — never a bare true/null.
    public struct Recovery: Codable, Equatable, Sendable {
        public var reasonCode: String
        public var command: String

        public init(reasonCode: String, command: String) {
            self.reasonCode = reasonCode
            self.command = command
        }
    }

    // MARK: - Already-gathered observations (resolver input)

    public struct Input: Equatable, Sendable {
        public var desiredState: DesiredStateObservation
        public var supervisor: SupervisorObservation
        public var binary: BinaryObservation
        public var activeHealth: ActiveHealthObservation
        public var receipt: ServeRuntimeReceipts.Reading
        /// Bounded internal install/repair observation only (§5.2 `starting`).
        public var converging: Bool
        /// Active obligations that make restart/update unsafe (§7 update ban).
        public var activeObligationCount: Int

        public init(
            desiredState: DesiredStateObservation,
            supervisor: SupervisorObservation,
            binary: BinaryObservation,
            activeHealth: ActiveHealthObservation,
            receipt: ServeRuntimeReceipts.Reading,
            converging: Bool = false,
            activeObligationCount: Int = 0
        ) {
            self.desiredState = desiredState
            self.supervisor = supervisor
            self.binary = binary
            self.activeHealth = activeHealth
            self.receipt = receipt
            self.converging = converging
            self.activeObligationCount = activeObligationCount
        }
    }

    public enum DesiredStateObservation: Equatable, Sendable {
        case known(ServeDesiredState.State)
        case unknown(reason: String)
    }

    public struct SupervisorObservation: Equatable, Sendable {
        public var kind: Supervisor.Kind
        public var label: String
        public var plistPresent: Bool
        /// `nil` means launchd load state is unknown — fail closed.
        public var loaded: Bool?
        public var authorization: Supervisor.Authorization
        public var pid: Int32?
        public var lastExitCode: Int?

        public init(
            kind: Supervisor.Kind = .launchAgent,
            label: String,
            plistPresent: Bool,
            loaded: Bool?,
            authorization: Supervisor.Authorization,
            pid: Int32? = nil,
            lastExitCode: Int? = nil
        ) {
            self.kind = kind
            self.label = label
            self.plistPresent = plistPresent
            self.loaded = loaded
            self.authorization = authorization
            self.pid = pid
            self.lastExitCode = lastExitCode
        }
    }

    public struct BinaryObservation: Equatable, Sendable {
        public var path: String
        public var expectedGitSha: String?
        public var runningGitSha: String?
        public var expectedCodeIdentity: CanonicalCLIInstall.CodeIdentity?
        public var runningCodeIdentity: CanonicalCLIInstall.CodeIdentity?

        public init(
            path: String,
            expectedGitSha: String?,
            runningGitSha: String?,
            expectedCodeIdentity: CanonicalCLIInstall.CodeIdentity?,
            runningCodeIdentity: CanonicalCLIInstall.CodeIdentity?
        ) {
            self.path = path
            self.expectedGitSha = expectedGitSha
            self.runningGitSha = runningGitSha
            self.expectedCodeIdentity = expectedCodeIdentity
            self.runningCodeIdentity = runningCodeIdentity
        }
    }

    public enum ActiveHealthObservation: Equatable, Sendable {
        case responded(daemonId: String, pid: Int32, respondedAt: Date)
        case noResponse(reason: String)
        case unknown(reason: String)
    }

    // MARK: - Pure resolver

    /// Maps already-gathered observations to one `ServeStatusJSON`. No I/O.
    public static func resolve(_ input: Input) -> ServeStatusJSON {
        let binary = resolveBinary(input.binary)
        let loadedKnown = input.supervisor.loaded
        let loaded = loadedKnown ?? false
        let supervisor = Supervisor(
            kind: input.supervisor.kind,
            label: input.supervisor.label,
            loaded: loaded,
            authorization: input.supervisor.authorization,
            pid: input.supervisor.pid,
            lastExitCode: input.supervisor.lastExitCode
        )

        let (daemon, healthMatched) = resolveDaemon(input: input)
        let (schedulers, missingRequired, failedRequired, stoppedRequired) =
            resolveSchedulers(input.receipt)

        let desired: DesiredState
        let desiredUnknown: String?
        switch input.desiredState {
        case .known(.enabled):
            desired = .enabled
            desiredUnknown = nil
        case .known(.disabled):
            desired = .disabled
            desiredUnknown = nil
        case .unknown(let reason):
            desired = .enabled
            desiredUnknown = reason
        }

        let decision = decideState(
            desired: desired,
            desiredUnknown: desiredUnknown,
            supervisor: input.supervisor,
            loadedKnown: loadedKnown,
            loaded: loaded,
            binary: binary,
            binaryObservation: input.binary,
            healthMatched: healthMatched,
            activeHealth: input.activeHealth,
            receipt: input.receipt,
            missingRequired: missingRequired,
            failedRequired: failedRequired,
            stoppedRequired: stoppedRequired,
            converging: input.converging,
            activeObligationCount: input.activeObligationCount
        )

        return ServeStatusJSON(
            schemaVersion: 2,
            desiredState: desired,
            state: decision.state,
            supervisor: supervisor,
            binary: binary,
            daemon: daemon,
            schedulers: schedulers,
            recovery: decision.recovery
        )
    }

    // MARK: - Internals

    private struct Decision {
        let state: State
        let recovery: Recovery?
    }

    private static func resolveBinary(_ obs: BinaryObservation) -> Binary {
        Binary(
            path: obs.path,
            expectedGitSha: obs.expectedGitSha,
            runningGitSha: obs.runningGitSha,
            expectedCodeIdentity: obs.expectedCodeIdentity,
            runningCodeIdentity: obs.runningCodeIdentity,
            matches: binaryMatches(obs)
        )
    }

    /// Code-identity comparison: equal, differs, or unrecorded.
    /// A `version`-only identity is not comparable (§7 version→identity ban).
    /// Absence of a comparable cdhash is unrecorded — never "differs".
    enum CodeIdentityRelation: Equatable, Sendable {
        case equal
        case differs
        case unrecorded
    }

    /// Non-empty cdhash only. Version strings never prove sameness.
    static func comparableCdhash(_ identity: CanonicalCLIInstall.CodeIdentity?) -> String? {
        guard let hash = identity?.cdhash?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hash.isEmpty else {
            return nil
        }
        return hash
    }

    static func compareCodeIdentity(
        expected: CanonicalCLIInstall.CodeIdentity?,
        running: CanonicalCLIInstall.CodeIdentity?
    ) -> CodeIdentityRelation {
        switch (comparableCdhash(expected), comparableCdhash(running)) {
        case (let expectedHash?, let runningHash?) where expectedHash == runningHash:
            return .equal
        case (_?, _?):
            return .differs
        default:
            return .unrecorded
        }
    }

    /// Binary agreement for `matches` / healthy. False only when a difference is
    /// observed (app-bundle path, unequal git sha, or two known differing
    /// cdhashes). Unrecorded identity with equal git sha is not a mismatch —
    /// absence yields no observation, never an inferred failure.
    private static func binaryMatches(_ obs: BinaryObservation) -> Bool {
        if obs.path.split(separator: "/").contains(where: { $0.hasSuffix(".app") }) {
            return false
        }
        guard let expectedSha = obs.expectedGitSha,
              let runningSha = obs.runningGitSha,
              expectedSha == runningSha else {
            return false
        }
        switch compareCodeIdentity(
            expected: obs.expectedCodeIdentity,
            running: obs.runningCodeIdentity
        ) {
        case .equal, .unrecorded:
            return true
        case .differs:
            return false
        }
    }

    /// Recovery when `matches` is false. `SERVE_BINARY_MISMATCH` only for two
    /// known differing identities (or sha/path disagreement with a comparable
    /// pair that did not differ). Unrecorded alone never reaches here when
    /// git shas are equal; if sha/path fails while identity is unrecorded,
    /// name that with `SERVE_BINARY_IDENTITY_UNRECORDED` + `alln install-cli`
    /// — repair does not record an identity.
    static func binaryMismatchRecovery(
        expected: CanonicalCLIInstall.CodeIdentity?,
        running: CanonicalCLIInstall.CodeIdentity?
    ) -> Recovery {
        switch compareCodeIdentity(expected: expected, running: running) {
        case .differs:
            return Recovery(reasonCode: "SERVE_BINARY_MISMATCH", command: "alln serve repair")
        case .unrecorded:
            return Recovery(
                reasonCode: "SERVE_BINARY_IDENTITY_UNRECORDED",
                command: "alln install-cli"
            )
        case .equal:
            return Recovery(reasonCode: "SERVE_BINARY_MISMATCH", command: "alln serve repair")
        }
    }

    private static func resolveDaemon(input: Input) -> (Daemon, healthMatched: Bool) {
        let receiptDaemonId: String?
        let receiptPid: Int32?
        let startedAt: Date?
        switch input.receipt {
        case .present(let id, let pid, let started, _):
            receiptDaemonId = id
            receiptPid = pid
            startedAt = started
        case .absent, .unreadable:
            receiptDaemonId = nil
            receiptPid = nil
            startedAt = nil
        }

        switch input.activeHealth {
        case .responded(let daemonId, let pid, let respondedAt):
            let matched = receiptDaemonId == daemonId && receiptPid == pid
            return (
                Daemon(
                    daemonId: receiptDaemonId ?? daemonId,
                    pid: receiptPid ?? pid,
                    startedAt: startedAt,
                    activeHealthRespondedAt: matched ? respondedAt : nil
                ),
                matched
            )
        case .noResponse, .unknown:
            return (
                Daemon(
                    daemonId: receiptDaemonId,
                    pid: receiptPid,
                    startedAt: startedAt,
                    activeHealthRespondedAt: nil
                ),
                false
            )
        }
    }

    private static func resolveSchedulers(
        _ receipt: ServeRuntimeReceipts.Reading
    ) -> (
        schedulers: [Scheduler],
        missingRequired: [String],
        failedRequired: [String],
        stoppedRequired: [String]
    ) {
        switch receipt {
        case .absent, .unreadable:
            return ([], ServeRuntimeReceipts.requiredSchedulerIds.sorted(), [], [])
        case .present(_, _, _, let rows):
            let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            var missing: [String] = []
            var failed: [String] = []
            var stopped: [String] = []
            for id in ServeRuntimeReceipts.requiredSchedulerIds.sorted() {
                guard let row = byId[id] else {
                    missing.append(id)
                    continue
                }
                // Required `stopped` under a live matching handshake is
                // degradation (decideState). Without a live handshake, stand-down
                // stays on the supervisor path — do not treat as `.failed`.
                if row.state == .failed {
                    failed.append(id)
                } else if row.state == .stopped {
                    stopped.append(id)
                }
            }
            // Optional ids (cloudRelay): omit when absent; never paint failed;
            // stopped optional never degrades.
            let projected: [Scheduler] = rows
                .filter { row in
                    ServeRuntimeReceipts.requiredSchedulerIds.contains(row.id)
                        || ServeRuntimeReceipts.optionalSchedulerIds.contains(row.id)
                }
                .map {
                    Scheduler(
                        id: $0.id,
                        state: $0.state,
                        lastAttemptAt: $0.lastAttemptAt,
                        lastSuccessAt: $0.lastSuccessAt,
                        lastError: $0.lastError,
                        nextWakeAt: $0.nextWakeAt
                    )
                }
            return (projected, missing, failed, stopped)
        }
    }

    private static func decideState(
        desired: DesiredState,
        desiredUnknown: String?,
        supervisor: SupervisorObservation,
        loadedKnown: Bool?,
        loaded: Bool,
        binary: Binary,
        binaryObservation: BinaryObservation,
        healthMatched: Bool,
        activeHealth: ActiveHealthObservation,
        receipt: ServeRuntimeReceipts.Reading,
        missingRequired: [String],
        failedRequired: [String],
        stoppedRequired: [String],
        converging: Bool,
        activeObligationCount: Int
    ) -> Decision {
        // requiresApproval wins over other enabled-path states.
        if supervisor.authorization == .requiresApproval {
            return Decision(
                state: .requiresApproval,
                recovery: Recovery(
                    reasonCode: "SERVE_REQUIRES_APPROVAL",
                    command: "Open System Settings > General > Login Items & Extensions and enable \(supervisor.label)"
                )
            )
        }

        // Clean disabled: desired disabled and nothing loaded / no process.
        if desired == .disabled && desiredUnknown == nil && !loaded && supervisor.pid == nil {
            return Decision(state: .disabled, recovery: nil)
        }

        // Unknown inputs fail closed — never upgrade to healthy.
        if desiredUnknown != nil {
            return degraded("SERVE_UNKNOWN_DESIRED_STATE", "alln serve status --json",
                            obligations: activeObligationCount)
        }

        if case .unknown = activeHealth {
            return degraded("SERVE_UNKNOWN_ACTIVE_HEALTH", "alln serve repair",
                            obligations: activeObligationCount)
        }

        if case .unreadable = receipt {
            return degraded("SERVE_UNKNOWN_RECEIPT", "alln serve repair",
                            obligations: activeObligationCount)
        }

        if loadedKnown == nil {
            return degraded("SERVE_UNKNOWN_SUPERVISOR", "alln serve repair",
                            obligations: activeObligationCount)
        }

        if supervisor.authorization == .unknown {
            return degraded("SERVE_UNKNOWN_AUTHORIZATION", "alln serve status --json",
                            obligations: activeObligationCount)
        }

        // Bounded install/repair observation.
        if converging {
            return Decision(
                state: .starting,
                recovery: Recovery(
                    reasonCode: "SERVE_STARTING",
                    command: "alln serve status --json"
                )
            )
        }

        // Stand-down: loaded, exit 0, no process (§4.2 / §7 exit → restart).
        let isStandDown = loaded
            && supervisor.pid == nil
            && supervisor.lastExitCode == 0
            && !healthMatched
        if isStandDown {
            return degraded("SERVE_STAND_DOWN", "alln serve repair",
                            obligations: activeObligationCount)
        }

        // Narrow healthy: all six conditions, plus no stopped required rows
        // under the live matching handshake this healthy path already requires.
        // Unrecorded code identity with equal git sha yields matches == true
        // (absence is not a mismatch), so a correctly installed host is not
        // stuck degraded when the install record has no comparable cdhash.
        let isHealthy = desired == .enabled
            && supervisor.authorization == .enabled
            && loaded
            && healthMatched
            && binary.matches
            && missingRequired.isEmpty
            && failedRequired.isEmpty
            && stoppedRequired.isEmpty

        if isHealthy {
            return Decision(state: .healthy, recovery: nil)
        }

        // Degraded — name why (priority order).
        if !binary.matches {
            let recovery = binaryMismatchRecovery(
                expected: binaryObservation.expectedCodeIdentity,
                running: binaryObservation.runningCodeIdentity
            )
            return degraded(recovery.reasonCode, recovery.command,
                            obligations: activeObligationCount)
        }
        if !missingRequired.isEmpty {
            return degraded("SERVE_SCHEDULER_MISSING", "alln serve repair",
                            obligations: activeObligationCount)
        }
        if !failedRequired.isEmpty {
            return degraded("SERVE_SCHEDULER_FAILED", "alln serve repair",
                            obligations: activeObligationCount)
        }
        // Live matching handshake + required `stopped` is a contradiction, not
        // stand-down. Name the stopped ids. Without a matching handshake, leave
        // the supervisor/stand-down path above to decide.
        if loaded && healthMatched && !stoppedRequired.isEmpty {
            return degraded(
                "SERVE_SCHEDULER_STOPPED:\(stoppedRequired.joined(separator: ","))",
                "alln serve repair",
                obligations: activeObligationCount
            )
        }
        if !loaded {
            return degraded("SERVE_SUPERVISOR_NOT_LOADED", "alln serve repair",
                            obligations: activeObligationCount)
        }
        if !healthMatched {
            return degraded("SERVE_UNAVAILABLE", "alln serve repair",
                            obligations: activeObligationCount)
        }
        if desired == .disabled {
            return degraded("SERVE_DISABLE_INCOMPLETE", "alln serve disable",
                            obligations: activeObligationCount)
        }

        return degraded("SERVE_UNAVAILABLE", "alln serve repair",
                        obligations: activeObligationCount)
    }

    /// Busy obligations override the specific reason: never recommend restart.
    private static func degraded(
        _ reasonCode: String,
        _ command: String,
        obligations: Int
    ) -> Decision {
        if obligations > 0 {
            return Decision(
                state: .degraded,
                recovery: Recovery(
                    reasonCode: "SERVE_BUSY",
                    command: "alln serve status --json"
                )
            )
        }
        return Decision(
            state: .degraded,
            recovery: Recovery(reasonCode: reasonCode, command: command)
        )
    }
}

// MARK: - Codable (§5.2 keys always present, nulls explicit)

extension ServeStatusJSON: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, desiredState, state, supervisor, binary, daemon, schedulers, recovery
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        desiredState = try c.decode(DesiredState.self, forKey: .desiredState)
        state = try c.decode(State.self, forKey: .state)
        supervisor = try c.decode(Supervisor.self, forKey: .supervisor)
        binary = try c.decode(Binary.self, forKey: .binary)
        daemon = try c.decode(Daemon.self, forKey: .daemon)
        schedulers = try c.decode([Scheduler].self, forKey: .schedulers)
        recovery = try c.decodeIfPresent(Recovery.self, forKey: .recovery)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(desiredState, forKey: .desiredState)
        try c.encode(state, forKey: .state)
        try c.encode(supervisor, forKey: .supervisor)
        try c.encode(binary, forKey: .binary)
        try c.encode(daemon, forKey: .daemon)
        try c.encode(schedulers, forKey: .schedulers)
        try c.encode(recovery, forKey: .recovery)
    }
}

extension ServeStatusJSON.Supervisor: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, label, loaded, authorization, pid, lastExitCode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        loaded = try c.decode(Bool.self, forKey: .loaded)
        authorization = try c.decode(Authorization.self, forKey: .authorization)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        lastExitCode = try c.decodeIfPresent(Int.self, forKey: .lastExitCode)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(label, forKey: .label)
        try c.encode(loaded, forKey: .loaded)
        try c.encode(authorization, forKey: .authorization)
        try c.encode(pid, forKey: .pid)
        try c.encode(lastExitCode, forKey: .lastExitCode)
    }
}

extension ServeStatusJSON.Binary: Codable {
    private enum CodingKeys: String, CodingKey {
        case path, expectedGitSha, runningGitSha
        case expectedCodeIdentity, runningCodeIdentity, matches
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        expectedGitSha = try c.decodeIfPresent(String.self, forKey: .expectedGitSha)
        runningGitSha = try c.decodeIfPresent(String.self, forKey: .runningGitSha)
        expectedCodeIdentity = try c.decodeIfPresent(CanonicalCLIInstall.CodeIdentity.self, forKey: .expectedCodeIdentity)
        runningCodeIdentity = try c.decodeIfPresent(CanonicalCLIInstall.CodeIdentity.self, forKey: .runningCodeIdentity)
        matches = try c.decode(Bool.self, forKey: .matches)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
        try c.encode(expectedGitSha, forKey: .expectedGitSha)
        try c.encode(runningGitSha, forKey: .runningGitSha)
        try c.encode(expectedCodeIdentity, forKey: .expectedCodeIdentity)
        try c.encode(runningCodeIdentity, forKey: .runningCodeIdentity)
        try c.encode(matches, forKey: .matches)
    }
}

extension ServeStatusJSON.Daemon: Codable {
    private enum CodingKeys: String, CodingKey {
        case daemonId, pid, startedAt, activeHealthRespondedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        daemonId = try c.decodeIfPresent(String.self, forKey: .daemonId)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        activeHealthRespondedAt = try c.decodeIfPresent(Date.self, forKey: .activeHealthRespondedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(daemonId, forKey: .daemonId)
        try c.encode(pid, forKey: .pid)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(activeHealthRespondedAt, forKey: .activeHealthRespondedAt)
    }
}
