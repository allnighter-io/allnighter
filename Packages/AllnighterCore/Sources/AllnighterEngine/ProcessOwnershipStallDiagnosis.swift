import Foundation
#if canImport(Darwin)
import Darwin
#endif
import AllnighterCore

// Stall-cause diagnosis for owned worker trees (unattended auth-prompt wedge).
//
// Extends PO-F1 progress-stall machinery: before a bare "timeout" is the whole
// story, inspect the owned descendant snapshot and name what is wedged —
// credential helpers, askpass, SecurityAgent, or a frozen zero-CPU child.
//
// Pure classifier + Darwin tree sampling. Tests feed synthetic snapshots; the
// live path samples via sysctl / libproc. Does not run git.
//
// Limit (honest): non-interactive GIT_/SSH_ env vars do not suppress
// Security.framework Keychain modals; this diagnosis is what makes that wedge
// visible when it still happens.

extension ProcessOwnership {

    /// One process in an owned descendant snapshot (synthetic or live).
    public struct ProcessTreeNode: Sendable, Equatable {
        public var pid: Int32
        public var ppid: Int32
        public var name: String
        /// Cumulative user+system CPU µs when known; nil when unavailable.
        public var cpuMicroseconds: Int64?

        public init(pid: Int32, ppid: Int32, name: String, cpuMicroseconds: Int64? = nil) {
            self.pid = pid
            self.ppid = ppid
            self.name = name
            self.cpuMicroseconds = cpuMicroseconds
        }
    }

    /// Named stall cause for receipts / `alln ps` / timeout enrichment.
    public struct StallDiagnosis: Sendable, Equatable {
        public enum Kind: String, Sendable, Equatable, Codable {
            case interactiveAuthPrompt
            case frozenDescendant
        }

        public var kind: Kind
        /// Compact human line, e.g.
        /// `descendant blocked on interactive auth prompt (git-credential-osxkeychain / SecurityAgent), pid 46103`
        public var summary: String
        public var pid: Int32?
        public var processName: String?

        public init(kind: Kind, summary: String, pid: Int32? = nil, processName: String? = nil) {
            self.kind = kind
            self.summary = summary
            self.pid = pid
            self.processName = processName
        }

        /// Full timeout / stall headline for receipts.
        public func timeoutHeadline(stalledFor: TimeInterval? = nil) -> String {
            if let stalledFor, stalledFor > 0 {
                let minutes = Int((stalledFor / 60.0).rounded(.down))
                if minutes >= 1 {
                    return "worker turn stalled \(minutes)m — \(summary)"
                }
                let seconds = Int(stalledFor.rounded())
                return "worker turn stalled \(seconds)s — \(summary)"
            }
            return "worker turn stalled — \(summary)"
        }
    }

    private struct StallDiagnosisWire: Codable {
        var kind: String
        var summary: String
        var pid: Int32?
        var processName: String?
        var headline: String
    }

    /// Durable file name under a turn / run owner directory.
    public static let stallDiagnosisFileName = "stall_diagnosis.json"

    public static func stallDiagnosisURL(in directory: URL) -> URL {
        directory.appendingPathComponent(stallDiagnosisFileName)
    }

    public static func writeStallDiagnosis(_ diagnosis: StallDiagnosis, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let wire = StallDiagnosisWire(
            kind: diagnosis.kind.rawValue,
            summary: diagnosis.summary,
            pid: diagnosis.pid,
            processName: diagnosis.processName,
            headline: diagnosis.timeoutHeadline()
        )
        try CoreJSON.encode(wire).write(to: stallDiagnosisURL(in: directory), options: .atomic)
    }

    public static func readStallDiagnosis(in directory: URL) -> StallDiagnosis? {
        guard let data = try? Data(contentsOf: stallDiagnosisURL(in: directory)),
              let wire = try? CoreJSON.decode(StallDiagnosisWire.self, from: data),
              let kind = StallDiagnosis.Kind(rawValue: wire.kind) else {
            return nil
        }
        return StallDiagnosis(
            kind: kind,
            summary: wire.summary,
            pid: wire.pid,
            processName: wire.processName
        )
    }

    /// Persisted timeout headline when present (`worker turn stalled …`); else
    /// rebuilds from `readStallDiagnosis`.
    public static func readStallTimeoutHeadline(in directory: URL) -> String? {
        if let data = try? Data(contentsOf: stallDiagnosisURL(in: directory)),
           let wire = try? CoreJSON.decode(StallDiagnosisWire.self, from: data),
           !wire.headline.isEmpty {
            return wire.headline
        }
        return readStallDiagnosis(in: directory)?.timeoutHeadline()
    }

    /// Best-effort: turn dir, then run dir.
    public static func currentStallTimeoutHeadline() -> String? {
        if let turn = TurnOwnerDirectory.shared.get(),
           let headline = readStallTimeoutHeadline(in: turn) {
            return headline
        }
        if let run = RuntimeOwnershipContext.shared.runDirectory(),
           let headline = readStallTimeoutHeadline(in: run) {
            return headline
        }
        return nil
    }

    /// Record diagnosis into the active turn directory when set, else no-op.
    public static func recordTurnStallDiagnosis(_ diagnosis: StallDiagnosis) {
        guard let directory = TurnOwnerDirectory.shared.get() else { return }
        try? writeStallDiagnosis(diagnosis, in: directory)
    }

    // MARK: - Pure classifier

    /// Classify a synthetic or live descendant snapshot. Prefers interactive
    /// auth-prompt shapes; otherwise a zero-CPU descendant (excluding the root).
    /// Returns nil when nothing diagnostic is visible.
    public static func classifyStallCause(
        descendants: [ProcessTreeNode],
        rootPid: Int32
    ) -> StallDiagnosis? {
        let others = descendants.filter { $0.pid != rootPid && $0.pid > 0 }
        guard !others.isEmpty else { return nil }

        // Auth-prompt shapes (SecurityAgent may sit outside the pgid; credential
        // helpers usually remain in the owned tree).
        let authHits = others.filter { isInteractiveAuthPromptName($0.name) }
        if !authHits.isEmpty {
            let primary = preferredAuthPromptNode(authHits)
            let labels = uniqueAuthLabels(authHits.map(\.name))
            let joined = labels.joined(separator: " / ")
            return StallDiagnosis(
                kind: .interactiveAuthPrompt,
                summary: "descendant blocked on interactive auth prompt (\(joined)), pid \(primary.pid)",
                pid: primary.pid,
                processName: primary.name
            )
        }

        // Frozen zero-CPU descendant — generic wedge (hung build, deadlock, …).
        if let frozen = others.first(where: { ($0.cpuMicroseconds ?? 1) == 0 }) {
            let label = displayProcessName(frozen.name)
            return StallDiagnosis(
                kind: .frozenDescendant,
                summary: "descendant idle with zero CPU (\(label)), pid \(frozen.pid)",
                pid: frozen.pid,
                processName: frozen.name
            )
        }

        return nil
    }

    /// True when `name` matches credential-prompt / askpass / SecurityAgent shapes.
    public static func isInteractiveAuthPromptName(_ name: String) -> Bool {
        let base = (name as NSString).lastPathComponent.lowercased()
        if base == "securityagent" { return true }
        if base.contains("askpass") { return true }
        if base.hasPrefix("git-credential") { return true }
        if base.contains("git-credential") { return true }
        return false
    }

    private static func preferredAuthPromptNode(_ nodes: [ProcessTreeNode]) -> ProcessTreeNode {
        // Prefer the credential helper over SecurityAgent when both appear —
        // the helper is the owned descendant; SecurityAgent is often system-side.
        if let helper = nodes.first(where: {
            let n = $0.name.lowercased()
            return n.contains("git-credential") || n.contains("askpass")
        }) {
            return helper
        }
        return nodes[0]
    }

    private static func uniqueAuthLabels(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            let label = displayProcessName(name)
            let key = label.lowercased()
            if seen.insert(key).inserted {
                out.append(label)
            }
        }
        return out
    }

    private static func displayProcessName(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent
        let lower = base.lowercased()
        if lower.hasPrefix("git-credential") {
            // p_comm truncates at MAXCOMLEN (16); map truncated family to the
            // recognizable helper name from the founder incident.
            if !lower.contains("osxkeychain") {
                return "git-credential-osxkeychain"
            }
        }
        return base.isEmpty ? name : base
    }

    // MARK: - Live tree sampling

    /// Enumerate live descendants of `rootPid` (ppid walk), including the root.
    /// Best-effort; empty on failure. Does not invent processes outside the tree.
    public static func sampleDescendantTree(rootPid: Int32) -> [ProcessTreeNode] {
        guard rootPid > 1 else { return [] }
        #if os(macOS)
        let all = sampleAllProcesses()
        guard !all.isEmpty else { return [] }
        var children: [Int32: [Int32]] = [:]
        var byPid: [Int32: ProcessTreeNode] = [:]
        for node in all {
            byPid[node.pid] = node
            children[node.ppid, default: []].append(node.pid)
        }
        guard byPid[rootPid] != nil else { return [] }
        var result: [ProcessTreeNode] = []
        var stack: [Int32] = [rootPid]
        var seen = Set<Int32>()
        while let pid = stack.popLast() {
            guard seen.insert(pid).inserted else { continue }
            if var node = byPid[pid] {
                if node.cpuMicroseconds == nil {
                    node.cpuMicroseconds = processCPUMicroseconds(pid)
                }
                // Prefer libproc name when p_comm is truncated.
                if let full = processExecutableName(pid), !full.isEmpty {
                    node.name = full
                }
                result.append(node)
            }
            for child in children[pid] ?? [] {
                stack.append(child)
            }
        }
        return result
        #else
        return []
        #endif
    }

    /// Diagnose the owned tree for `identity` (descendants of pid + pgid members).
    public static func diagnoseOwnedTreeStall(identity: OwnerIdentity) -> StallDiagnosis? {
        var nodes = sampleDescendantTree(rootPid: identity.pid)
        if let pgid = identity.pgid, pgid > 1 {
            let members = processGroupMemberPids(pgid)
            let existing = Set(nodes.map(\.pid))
            for pid in members where !existing.contains(pid) {
                let name = processExecutableName(pid) ?? processCommName(pid) ?? "pid-\(pid)"
                nodes.append(ProcessTreeNode(
                    pid: pid,
                    ppid: 0,
                    name: name,
                    cpuMicroseconds: processCPUMicroseconds(pid)
                ))
            }
        }
        return classifyStallCause(descendants: nodes, rootPid: identity.pid)
    }

    /// After group kill: reap any still-live descendants of the owned root that
    /// left the process group (orphaned grandchildren). Best-effort SIGKILL only
    /// for pids still in the descendant set of `rootPid` at call time.
    public static func reapOrphanedDescendants(rootPid: Int32) {
        guard rootPid > 1 else { return }
        let nodes = sampleDescendantTree(rootPid: rootPid)
        for node in nodes where node.pid != rootPid {
            _ = kill(node.pid, SIGKILL)
        }
    }

    #if os(macOS)
    private static func sampleAllProcesses() -> [ProcessTreeNode] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: size_t = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count)
        let rc = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            var sz = size
            return sysctl(&mib, 4, ptr.baseAddress, &sz, nil, 0)
        }
        guard rc == 0 else { return [] }
        return buffer.compactMap { info -> ProcessTreeNode? in
            let pid = info.kp_proc.p_pid
            guard pid > 0 else { return nil }
            let ppid = info.kp_eproc.e_ppid
            let name = withUnsafePointer(to: info.kp_proc.p_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { String(cString: $0) }
            }
            return ProcessTreeNode(pid: pid, ppid: ppid, name: name)
        }
    }

    static func processCommName(_ pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let rc = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard rc == 0, size >= MemoryLayout<kinfo_proc>.stride else { return nil }
        return withUnsafePointer(to: info.kp_proc.p_comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { String(cString: $0) }
        }
    }

    /// Basename of the executable via `proc_name` (longer than p_comm).
    static func processExecutableName(_ pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 1024)
        let n = proc_name(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        let len = Int(n)
        return String(decoding: buffer.prefix(len).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    #else
    static func processCommName(_ pid: Int32) -> String? { nil }
    static func processExecutableName(_ pid: Int32) -> String? { nil }
    #endif
}
