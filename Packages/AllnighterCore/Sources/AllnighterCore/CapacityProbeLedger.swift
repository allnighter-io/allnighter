import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Durable record of vendor CLI processes the capacity probe spawned, so an
/// orphan cannot accumulate unnoticed.
///
/// ## Why this exists
///
/// On 2026-08-08 this host had **103 orphaned vendor CLI processes** — all
/// PPID=1, no controlling TTY, the oldest six days old, spanning three codex
/// versions and two grok versions. Load average was 12.75. A full-bench capacity
/// refresh failed 2 of 6 runs; after killing them, 6 of 6 passed in 6-7 seconds.
///
/// So the leak did not just waste memory: **it broke capacity**, by making the
/// machine slow enough that vendor TUIs missed their paint budget. And it did it
/// silently, for six days, with no signal until the numbers started going
/// missing.
///
/// The leak is **not reproducible on current code** — a clean refresh leaks
/// zero, and so does a forced-timeout run where every probe is killed mid-boot.
/// The corpses were historical, from before the scoped-kill work. This ledger is
/// therefore not a fix for a live bug; it is the missing *signal and sweep* so
/// that if it ever regresses, or a vendor changes how it spawns helpers, the
/// damage is bounded to one refresh instead of six days.
///
/// ## Why a ledger and not a heuristic
///
/// "Kill PPID=1 vendor CLIs with no TTY" would have cleaned this host — and
/// would also kill a user's deliberately backgrounded `claude` session, which is
/// indistinguishable by those signals. We may only reap what we can prove we
/// spawned.
///
/// Identity follows `ProcessOwnership`'s law: a pid alone is not an identity,
/// because pids are recycled. An entry is only actionable when the recorded
/// owner's pid **and** start time both still match — otherwise the owner is gone
/// and its children are orphans, or the pid now belongs to something innocent.
public struct CapacityProbeLedger: Sendable {

    public struct Entry: Codable, Equatable, Sendable {
        public var childPID: Int32
        /// The child's own process group, which is what gets signalled — the
        /// probe spawns each CLI as a group leader precisely so its helpers can
        /// be reaped with it.
        public var childPGID: Int32
        public var ownerPID: Int32
        /// Boot-relative start time of the OWNER. Guards against pid reuse: a
        /// recycled pid reads as a dead owner rather than a live one.
        public var ownerStartTicks: UInt64
        public var source: String
        public var spawnedAt: Date

        public init(
            childPID: Int32, childPGID: Int32, ownerPID: Int32,
            ownerStartTicks: UInt64, source: String, spawnedAt: Date
        ) {
            self.childPID = childPID
            self.childPGID = childPGID
            self.ownerPID = ownerPID
            self.ownerStartTicks = ownerStartTicks
            self.source = source
            self.spawnedAt = spawnedAt
        }
    }

    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterSupportRoot.config
            .appendingPathComponent("capacity_probe_children.json")
    }

    // MARK: - Storage

    public func load() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }

    public func save(_ entries: [Entry]) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func record(_ entry: Entry) {
        var entries = load()
        entries.removeAll { $0.childPID == entry.childPID }
        entries.append(entry)
        save(entries)
    }

    public func forget(childPID: Int32) {
        let entries = load().filter { $0.childPID != childPID }
        save(entries)
    }

    // MARK: - Sweep

    /// What a sweep should do with each entry.
    ///
    /// Pure, so the decision is testable without spawning or killing anything —
    /// the part that must never be wrong is *which* processes we are willing to
    /// signal.
    public enum Verdict: Equatable, Sendable {
        /// Owner still alive: its probe is presumably still running. Leave it.
        case keep
        /// Owner gone and child gone: nothing to kill, just stop tracking.
        case forget
        /// Owner gone, child still alive: an orphan we created. Reap it.
        case reap(pgid: Int32)
    }

    public static func verdict(
        for entry: Entry,
        ownerIsAlive: (Int32, UInt64) -> Bool,
        childIsAlive: (Int32) -> Bool
    ) -> Verdict {
        if ownerIsAlive(entry.ownerPID, entry.ownerStartTicks) { return .keep }
        guard childIsAlive(entry.childPID) else { return .forget }
        // Never signal pgid 0 or 1 — that would mean "every process in my group"
        // or init. A malformed entry is forgotten, not acted on.
        guard entry.childPGID > 1 else { return .forget }
        return .reap(pgid: entry.childPGID)
    }

    /// Reap orphans and prune the ledger. Returns how many were killed.
    @discardableResult
    public func sweep(
        ownerIsAlive: (Int32, UInt64) -> Bool = CapacityProbeLedger.processIsAlive,
        childIsAlive: (Int32) -> Bool = { CapacityProbeLedger.processIsAlive($0, nil) },
        kill killGroup: (Int32) -> Void = { pgid in
            #if canImport(Darwin)
            _ = killpg(pgid, SIGKILL)
            #endif
        }
    ) -> Int {
        var survivors: [Entry] = []
        var reaped = 0
        for entry in load() {
            switch Self.verdict(for: entry, ownerIsAlive: ownerIsAlive, childIsAlive: childIsAlive) {
            case .keep:
                survivors.append(entry)
            case .forget:
                continue
            case .reap(let pgid):
                killGroup(pgid)
                reaped += 1
            }
        }
        save(survivors)
        return reaped
    }

    // MARK: - Process identity

    /// Alive **and** the same process we recorded. `nil` startTicks skips the
    /// identity check, for cases where only liveness is being asked.
    public static func processIsAlive(_ pid: Int32, _ startTicks: UInt64?) -> Bool {
        guard pid > 0 else { return false }
        #if canImport(Darwin)
        var exists = kill(pid, 0) == 0
        if !exists, errno == EPERM { exists = true }
        guard exists else { return false }
        guard let startTicks else { return true }
        guard let actual = startTimeTicks(of: pid) else { return false }
        return actual == startTicks
        #else
        return false
        #endif
    }

    /// Process start time, as microseconds since the epoch. Used only for
    /// identity comparison, never displayed.
    public static func startTimeTicks(of pid: Int32) -> UInt64? {
        #if canImport(Darwin)
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = mib.withUnsafeMutableBufferPointer { pointer -> Int32 in
            sysctl(pointer.baseAddress, u_int(pointer.count), &info, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_starttime
        return UInt64(started.tv_sec) &* 1_000_000 &+ UInt64(started.tv_usec)
        #else
        return nil
        #endif
    }

    /// Identity for the current process, for recording as an owner.
    public static func currentOwner() -> (pid: Int32, startTicks: UInt64) {
        let pid = ProcessInfo.processInfo.processIdentifier
        return (pid, startTimeTicks(of: pid) ?? 0)
    }
}
