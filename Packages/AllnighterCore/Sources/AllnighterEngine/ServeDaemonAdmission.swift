import Foundation
import AllnighterCore

/// Who gets to be `alln serve`.
///
/// Until now nothing enforced exclusivity: `ServeDaemonStore` records liveness
/// but is not a lock. On 2026-08-08 the dogfood host had **four** daemons
/// running, the oldest nine days old, each running a different build and each
/// running the full scheduler set.
///
/// Two distinct harms, and the second is the one that bites daily:
///
/// 1. Duplicate schedulers. Every daemon runs Pending wake, Boost seed,
///    vendor-backoff, notifications and capacity refresh.
/// 2. **Stale code keeps running.** `rebuild_cli.sh` replaces the binary on
///    PATH, but a daemon started nine days ago goes on executing nine-day-old
///    logic. Every serve-hosted fix silently fails to take effect, and nothing
///    says so. That is the fix-restart-fix-restart loop the founder asked to
///    close.
///
/// Identity is the git sha, not the version string: two builds of the same
/// version are different code, and the whole point is noticing that.
public enum ServeDaemonAdmission {

    public enum Decision: Equatable, Sendable {
        /// No live daemon. Any stale record should be cleared first.
        case start
        /// An identical build is already serving. Starting a second one buys
        /// nothing and doubles every schedule.
        case refuse(pid: Int32, version: String)
        /// A DIFFERENT build is serving — almost always an older one that
        /// predates a rebuild. The newcomer takes over, because the alternative
        /// is stale code winning by seniority.
        case supersede(pid: Int32, version: String, gitSha: String)
    }

    /// Decide against the recorded daemon, if any.
    ///
    /// `isAlive` is injected so this stays pure and testable — the real
    /// implementation is `kill(pid, 0)`.
    public static func decide(
        existing: ServeDaemonRecord?,
        isAlive: (Int32) -> Bool,
        myGitSha: String = AllnighterBuildInfo.gitSha
    ) -> Decision {
        guard let existing else { return .start }
        guard existing.pid > 0, isAlive(existing.pid) else {
            // A dead pid means the record outlived its process — the same
            // "a claim may not outlive its evidence" rule the probe cache
            // learned today.
            return .start
        }
        if existing.binaryGitSha == myGitSha {
            return .refuse(pid: existing.pid, version: existing.binaryVersion)
        }
        return .supersede(
            pid: existing.pid,
            version: existing.binaryVersion,
            gitSha: existing.binaryGitSha)
    }

    /// True when a process exists and we may signal it.
    public static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        #if canImport(Darwin)
        if kill(pid, 0) == 0 { return true }
        // EPERM means it exists but belongs to someone else — still alive.
        return errno == EPERM
        #else
        return false
        #endif
    }

    /// Other live `alln serve` processes, from the process table.
    ///
    /// The record alone is not enough, proven on the dogfood host: three daemons
    /// were running with NO record on disk at all. One shared record file means
    /// the last process to exit clears it for everyone, so a daemon that outlives
    /// a sibling's shutdown becomes invisible — and daemons started before this
    /// admission existed never recorded themselves in the first place.
    ///
    /// Deliberately narrow: the executable's last path component must be exactly
    /// `alln` and the first argument exactly `serve`. A user's editor with
    /// "alln serve" in its title, or an `alln serve --health` read, must never
    /// match.
    public static func runningServePIDs(
        excluding selfPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        listing: () -> String? = defaultProcessListing
    ) -> [Int32] {
        guard let output = listing() else { return [] }
        var pids: [Int32] = []
        for line in output.split(separator: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " ") else { continue }
            guard let pid = Int32(trimmed[trimmed.startIndex..<space]), pid != selfPID else { continue }
            let command = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
            let parts = command.split(separator: " ")
            guard parts.count >= 2 else { continue }
            guard (parts[0].split(separator: "/").last.map(String.init) ?? "") == "alln" else { continue }
            guard parts[1] == "serve" else { continue }
            // `--health` is a read, not a daemon.
            guard !parts.contains("--health") else { continue }
            pids.append(pid)
        }
        return pids
    }

    public static func defaultProcessListing() -> String? {
        #if canImport(Darwin)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid=,args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8).map { "header\n" + $0 }
        #else
        return nil
        #endif
    }

    /// Ask a superseded daemon to stop, then confirm it did.
    ///
    /// TERM first so it can clear its own record and stop its schedulers
    /// cleanly; KILL only if it will not go. Returns false if it outlived both,
    /// which the caller must treat as "do not start" rather than pressing on —
    /// two daemons is the condition being fixed.
    @discardableResult
    public static func stop(
        pid: Int32,
        graceSeconds: TimeInterval = 5,
        isAlive: (Int32) -> Bool = processIsAlive,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        signal: (Int32, Int32) -> Void = { pid, sig in
            #if canImport(Darwin)
            _ = kill(pid, sig)
            #endif
        }
    ) -> Bool {
        guard pid > 0 else { return true }
        #if canImport(Darwin)
        signal(pid, SIGTERM)
        var waited: TimeInterval = 0
        while waited < graceSeconds {
            if !isAlive(pid) { return true }
            sleep(0.2)
            waited += 0.2
        }
        signal(pid, SIGKILL)
        waited = 0
        while waited < 2 {
            if !isAlive(pid) { return true }
            sleep(0.2)
            waited += 0.2
        }
        return !isAlive(pid)
        #else
        return true
        #endif
    }
}
