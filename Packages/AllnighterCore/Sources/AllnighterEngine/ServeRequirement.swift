import Foundation
import AllnighterCore

/// Shared preflight for the **write of a deferred obligation** that only the
/// supervised `alln serve` daemon will claim (wake ticket, park, scheduled
/// notification, Boost seed, vendor-backoff continuation, cloud-relay entry).
///
/// Observes active health through the loopback handshake
/// (`ServeHealthClient` via `ServeDaemonProbe`) — never a pid-only check or a
/// plist check. A live pid with nothing listening is a refusal.
///
/// **Scope (AGENTS.md + Alln_Serve_Hotfixes §2.3):**
/// - Gates the write of deferred work, never command entry.
/// - `alln run` and an attended `alln loop` turn stay runnable with serve dead.
/// - This is the only product site allowed to refuse for serve unhealth.
public struct ServeRequirement: Sendable {
    public static let recoveryCommand = "alln serve repair"
    public static let errorCode = "SERVE_UNAVAILABLE"

    public struct Refusal: Error, Equatable, Sendable {
        /// Stable catalog code (`SERVE_UNAVAILABLE`).
        public let code: String
        /// Observed coordinator state plus handshake detail when relevant.
        public let observedState: String
        /// Human/agent message naming the observed state and recovery command.
        public let message: String
        /// Always `alln serve repair` — the one supported recovery.
        public let recoveryCommand: String
        /// Full health snapshot used to form the refusal (for tests / JSON).
        public let health: CoordinatorHealth
        /// Why the caller needed serve (diagnostics only; not a second veto).
        public let reason: String

        public init(
            code: String = ServeRequirement.errorCode,
            observedState: String,
            message: String,
            recoveryCommand: String = ServeRequirement.recoveryCommand,
            health: CoordinatorHealth,
            reason: String
        ) {
            self.code = code
            self.observedState = observedState
            self.message = message
            self.recoveryCommand = recoveryCommand
            self.health = health
            self.reason = reason
        }
    }

    public let probe: ServeDaemonProbe
    public let healthClient: ServeHealthClient
    public let binaryVersion: String

    public init(
        probe: ServeDaemonProbe = ServeDaemonProbe(),
        healthClient: ServeHealthClient = ServeHealthClient(),
        binaryVersion: String = AllnighterVersionIdentity.binaryVersion
    ) {
        self.probe = probe
        self.healthClient = healthClient
        self.binaryVersion = binaryVersion
    }

    /// Succeeds only when the supervised daemon answers the active handshake
    /// (state available **and** loopback listening with matching identity).
    public func require(reason: String) -> Result<Void, Refusal> {
        let health = probe.health(
            binaryVersion: binaryVersion,
            healthClient: healthClient
        )
        if health.state == .available && health.loopback.listening {
            return .success(())
        }

        let observed = Self.observedStateDescription(health)
        let message = """
        cannot write deferred obligation (\(reason)): serve is not actively healthy \
        (observed: \(observed)). Run `\(Self.recoveryCommand)`.
        """
        return .failure(Refusal(
            observedState: observed,
            message: message,
            health: health,
            reason: reason
        ))
    }

    /// Run `write` only after a healthy handshake. On refusal, `write` is never
    /// called — the caller's store stays unchanged.
    public func writeIfHealthy<T>(
        reason: String,
        write: () throws -> T
    ) rethrows -> Result<T, Refusal> {
        switch require(reason: reason) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success:
            return .success(try write())
        }
    }

    public static func observedStateDescription(_ health: CoordinatorHealth) -> String {
        switch health.state {
        case .foregroundOnly:
            return "foregroundOnly"
        case .unavailable:
            return "unavailable"
        case .available:
            if health.loopback.listening {
                return "available"
            }
            if let detail = health.loopback.detail, !detail.isEmpty {
                return "available_not_listening (\(detail))"
            }
            return "available_not_listening"
        }
    }
}
