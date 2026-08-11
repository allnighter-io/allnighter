import Foundation

/// Read-only observation of the `com.allnighter.resident-coordinator`
/// LaunchAgent (SC-S00, docs/phases/Serve_Continuity.md §3.4).
///
/// Pure: plist existence plus one `launchctl print` listing, classified by the
/// single wedge rule below. Never fakes liveness — a live job pid reads
/// `running`, an unreadable listing reads `unknown`, a missing plist reads
/// `absent`, and only the encoded wedge rule fails closed. No register,
/// repair, or bootout here (that is SC-S01).
public struct ServeLaunchAgentStatus: Sendable {
    public static let label = "com.allnighter.resident-coordinator"

    public enum State: String, Codable, Sendable {
        case running, wedged, absent, unknown
    }

    /// Whether `launchctl` was consulted for this observation. Display `detail` is not this contract.
    public enum LaunchctlConsultability: String, Codable, Equatable, Sendable {
        /// `launchctl print` was attempted and failed — loaded is unknown.
        case couldNotConsult
        /// `launchctl print` succeeded, or was not required (e.g. absent plist).
        case consulted
    }

    public struct Observation: Codable, Equatable, Sendable {
        public var state: State
        public var pid: Int32?
        public var lastExitCode: Int?
        public var detail: String
        /// Structured consult signal. `nil` is unclassifiable — never infer from `detail`.
        public var launchctlConsultability: LaunchctlConsultability?

        public init(
            state: State,
            pid: Int32? = nil,
            lastExitCode: Int? = nil,
            detail: String,
            launchctlConsultability: LaunchctlConsultability? = nil
        ) {
            self.state = state
            self.pid = pid
            self.lastExitCode = lastExitCode
            self.detail = detail
            self.launchctlConsultability = launchctlConsultability
        }
    }

    /// Live `launchctl print` failed (label not loaded or launchctl errored).
    public struct PrintError: Error, Equatable, Sendable {
        public let terminationStatus: Int32
        public init(terminationStatus: Int32) { self.terminationStatus = terminationStatus }
    }

    public let plistURL: URL
    public let plistExists: @Sendable (URL) -> Bool
    public let printListing: @Sendable () throws -> String

    public init(
        plistURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(ServeLaunchAgentStatus.label).plist"),
        plistExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        printListing: (@Sendable () throws -> String)? = nil
    ) {
        self.plistURL = plistURL
        self.plistExists = plistExists
        self.printListing = printListing ?? { try Self.livePrintListing() }
    }

    public func observe() -> Observation {
        guard plistExists(plistURL) else {
            return Observation(
                state: .absent,
                detail: "no \(Self.label) plist installed",
                launchctlConsultability: .consulted
            )
        }
        let listing: String
        do {
            listing = try printListing()
        } catch {
            // Producer knows launchctl could not be consulted — declare it; detail stays display-only.
            return Observation(
                state: .unknown,
                detail: "\(Self.label) plist present but launchctl print failed (job not loaded)",
                launchctlConsultability: .couldNotConsult
            )
        }
        let state = Self.stringValue("state", in: listing)
        let pid = Self.intValue("pid", in: listing).map(Int32.init)
        let lastExitCode = Self.intValue("last exit code", in: listing)
        let activeCount = Self.intValue("active count", in: listing)
        if Self.isWedged(state: state, pid: pid, lastExitCode: lastExitCode, activeCount: activeCount, listing: listing) {
            return Observation(
                state: .wedged, pid: pid, lastExitCode: lastExitCode,
                detail: "\(Self.label) wedged: spawn scheduled/inactive, last exit \(lastExitCode.map(String.init) ?? "unknown"), no live job pid",
                launchctlConsultability: .consulted
            )
        }
        if let pid {
            return Observation(
                state: .running, pid: pid, lastExitCode: lastExitCode,
                detail: "\(Self.label) running (pid \(pid))",
                launchctlConsultability: .consulted
            )
        }
        return Observation(
            state: .unknown, lastExitCode: lastExitCode,
            detail: "\(Self.label) loaded but not running and not wedged (state \(state ?? "unknown"))",
            launchctlConsultability: .consulted
        )
    }

    /// The one wedge rule (SC-S00 behavior §2). Wedged = launchd reports the
    /// job inactive (spawn scheduled or equivalent, no live pid) AND (last
    /// exit 78 / EX_CONFIG or LWCR-managed properties) — OR last exit 78 with
    /// zero active count. A live job pid is `running`, never wedged.
    static func isWedged(state: String?, pid: Int32?, lastExitCode: Int?, activeCount: Int?, listing: String) -> Bool {
        guard pid == nil else { return false }
        let lwcrMarked = listing.range(of: "needs LWCR", options: .caseInsensitive) != nil
            || listing.range(of: "managed LWCR", options: .caseInsensitive) != nil
        let spawnScheduledOrInactive = state?.lowercased() != "running"
        let ruleA = spawnScheduledOrInactive && (lastExitCode == 78 || lwcrMarked)
        let ruleB = lastExitCode == 78 && activeCount == 0
        return ruleA || ruleB
    }

    /// Live `launchctl print gui/<uid>/<label>`. Never called from unit tests —
    /// tests inject `printListing` fixtures.
    private static func livePrintListing() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PrintError(terminationStatus: process.terminationStatus)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func intValue(_ key: String, in listing: String) -> Int? {
        guard let raw = stringValue(key, in: listing) else { return nil }
        return Int(raw)
    }

    private static func stringValue(_ key: String, in listing: String) -> String? {
        for line in listing.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key) = ") else { continue }
            return String(trimmed.dropFirst("\(key) = ".count))
        }
        return nil
    }
}
