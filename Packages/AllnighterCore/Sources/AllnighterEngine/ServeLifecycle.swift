import Foundation

/// Product-owned **removal** of the unsupported CODE_RED LaunchAgent
/// (`com.allnighter.resident-coordinator`) — SC-S01, docs/phases/Serve_Continuity.md
/// §3.2/§4. The hand-dropped KeepAlive plist predates lifecycle ownership and
/// thrashes (spawn scheduled / EX_CONFIG 78 / LWCR) instead of supervising;
/// `remove` boots the label out of launchd and deletes the plist.
///
/// Removal only. This type never registers, enables, or re-installs an agent —
/// supported enablement (SMAppService) is SC-S04 and founder-gated. The wedge
/// rule itself is not duplicated here; callers observe with
/// `ServeLaunchAgentStatus` (SC-S00) and call `remove` when the observation is
/// not `.absent`.
public struct ServeLifecycle: Sendable {
    public static let label = ServeLaunchAgentStatus.label

    public enum RemovalOutcome: String, Codable, Sendable {
        /// Bootout settled (or the job was not loaded) and the plist is gone.
        case removed
        /// Nothing was installed — no-op success.
        case absent
        /// Bootout or plist deletion failed; the orphan may still be live.
        case failed
    }

    public struct RemovalResult: Codable, Equatable, Sendable {
        public var outcome: RemovalOutcome
        public var bootoutAttempted: Bool
        public var plistDeleted: Bool
        public var detail: String

        public init(outcome: RemovalOutcome, bootoutAttempted: Bool, plistDeleted: Bool, detail: String) {
            self.outcome = outcome
            self.bootoutAttempted = bootoutAttempted
            self.plistDeleted = plistDeleted
            self.detail = detail
        }
    }

    /// `launchctl bootout` failed for a reason other than "not loaded".
    public struct BootoutError: Error, Equatable, Sendable {
        public let terminationStatus: Int32
        public let message: String
        public init(terminationStatus: Int32, message: String) {
            self.terminationStatus = terminationStatus
            self.message = message
        }
    }

    public let plistURL: URL
    /// Boots the label out of `gui/<uid>`. "Not loaded / no such service" is
    /// success for removal; any other failure throws. Injectable — unit tests
    /// must never run a live bootout against the host.
    public let bootout: @Sendable (String) throws -> Void
    public let plistExists: @Sendable (URL) -> Bool
    public let removePlist: @Sendable (URL) throws -> Void

    public init(
        plistURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(ServeLifecycle.label).plist"),
        bootout: (@Sendable (String) throws -> Void)? = nil,
        plistExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        removePlist: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) {
        self.plistURL = plistURL
        self.bootout = bootout ?? Self.liveBootout
        self.plistExists = plistExists
        self.removePlist = removePlist
    }

    /// Full `alln serve repair` orchestration, testable with fixtures: absent
    /// observation is a no-op success (no bootout, no delete); anything else —
    /// wedged, running, or an orphan plist that will not print — is removed.
    public func repair(observation: ServeLaunchAgentStatus.Observation) -> RepairReport {
        guard observation.state != .absent else {
            return RepairReport(outcome: .absent, observedState: observation.state,
                                observedDetail: observation.detail, removal: nil)
        }
        let removal = remove()
        return RepairReport(outcome: removal.outcome, observedState: observation.state,
                            observedDetail: observation.detail, removal: removal)
    }

    public struct RepairReport: Codable, Equatable, Sendable {
        public var outcome: RemovalOutcome
        public var observedState: ServeLaunchAgentStatus.State
        public var observedDetail: String
        /// Nil when the observation was absent (no-op) — nothing was attempted.
        public var removal: RemovalResult?

        public init(outcome: RemovalOutcome, observedState: ServeLaunchAgentStatus.State,
                    observedDetail: String, removal: RemovalResult?) {
            self.outcome = outcome
            self.observedState = observedState
            self.observedDetail = observedDetail
            self.removal = removal
        }
    }

    /// Boot out the label (ignoring not-loaded) and delete the plist if one is
    /// installed. Structured outcome; never fakes success — a real bootout or
    /// delete failure reads `failed`, not `removed`.
    public func remove() -> RemovalResult {
        var bootoutFailure: String?
        do {
            try bootout(Self.label)
        } catch {
            bootoutFailure = "\(error)"
        }
        var plistDeleted = false
        var deleteFailure: String?
        if plistExists(plistURL) {
            do {
                try removePlist(plistURL)
                plistDeleted = true
            } catch {
                deleteFailure = "\(error)"
            }
        }
        if let bootoutFailure {
            return RemovalResult(outcome: .failed, bootoutAttempted: true, plistDeleted: plistDeleted,
                                 detail: "\(Self.label) bootout failed: \(bootoutFailure)")
        }
        if let deleteFailure {
            return RemovalResult(outcome: .failed, bootoutAttempted: true, plistDeleted: false,
                                 detail: "\(Self.label) plist delete failed: \(deleteFailure)")
        }
        let plistNote = plistDeleted ? "plist deleted" : "no plist installed"
        return RemovalResult(outcome: .removed, bootoutAttempted: true, plistDeleted: plistDeleted,
                             detail: "\(Self.label) removed: bootout settled, \(plistNote)")
    }

    /// Live `launchctl bootout gui/<uid>/<label>`. Never called from unit
    /// tests — tests inject `bootout` fixtures. "Could not find service" /
    /// "not loaded" means there was nothing to boot out: success for removal.
    private static func liveBootout(label: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        let pipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = message.lowercased()
        if lower.contains("could not find service") || lower.contains("not loaded") || lower.contains("no such process") {
            return
        }
        throw BootoutError(terminationStatus: process.terminationStatus, message: message)
    }
}
