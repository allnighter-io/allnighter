import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import AllnighterCore

/// The real `ACPTransport`: spawns a long-lived ACP worker process and wires its stdin/stdout to an
/// `ACPSession` (Warm_Single_Lane_Chat §4b). One process stays warm — the working-tree index +
/// agent runtime load ONCE; every turn after is model-time only.
///
/// stdin: `send` writes one newline-framed JSON-RPC line (a pipe write, synchronous).
/// stdout: a readability handler splits the byte stream into newline-delimited lines and yields them
/// on `inboundLines()`. stderr is discarded. The inbound stream finishes when the process exits.
public final class ProcessACPTransport: ACPTransport, @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let inbound: AsyncStream<String>
    private let inboundCont: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var buffer = Data()

    /// - command: CLI binary — absolute path, or bare name resolved via `/usr/bin/env`.
    /// - profile: vendor spawn recipe (grok stdio vs cursor `acp`).
    /// - cwd: the REAL repo root (indexed once, warm thereafter).
    public init(command: String, profile: ACPTransportProfile, cwd: String, extraEnv: [String: String] = [:]) throws {
        (inbound, inboundCont) = AsyncStream<String>.makeStream()

        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = profile.spawnArgs
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + profile.spawnArgs
        }
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice  // drain-free: never fills + blocks the agent

        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnv { env[k] = v }
        process.environment = env

        let cont = inboundCont
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ingest(data, cont)
        }
        process.terminationHandler = { _ in cont.finish() }

        try process.run()
        // Best-effort process-group leadership so terminate() can kill grandchildren
        // (same ownership law as PO-S02; Foundation.Process has no SETPGROUP at spawn —
        // relay/dev-turn workers use ProcessGroupCommandRunner's posix_spawn path).
        let pid = process.processIdentifier
        if pid > 1 {
            setpgid(pid, pid)
        }
    }

    private func ingest(_ data: Data, _ cont: AsyncStream<String>.Continuation) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        let newline = Data([0x0A])
        while let nl = buffer.range(of: newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<nl.upperBound)
            if let s = String(data: lineData, encoding: .utf8),
               !s.trimmingCharacters(in: .whitespaces).isEmpty {
                cont.yield(s)
            }
        }
    }

    public func send(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        lock.lock(); defer { lock.unlock() }
        try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    public func inboundLines() -> AsyncStream<String> { inbound }

    /// Stop the warm worker (thread closed / idle teardown / crash recovery).
    /// Routes through ProcessOwnership group kill when a pgid was established.
    public func terminate() {
        if process.isRunning {
            let pid = process.processIdentifier
            if pid > 1 {
                // Recorded pgid == pid after setpgid in init (never invent blindly for
                // unrelated pids — only signal the process we ourselves launched).
                ProcessOwnership.terminateProcessGroup(pgid: pid)
            } else {
                process.terminate()
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        inboundCont.finish()
    }
}
