import Foundation
import AllnighterCore

/// Harness-owned proof-of-record runner (`docs/phases/Process_Ownership.md` PO-S04).
///
/// Revives the PRJ-S12 **bounded-subprocess** shape (declared commands as
/// `/bin/sh -c` at the project root, hard timeout, captured exit + tail) without
/// resurrecting WorkOrder/VerificationRecord. Callers **must** inject a
/// process-group command runner (`ProcessGroupCommandRunner` with
/// `spawnKind: .harnessProof`) — this type never owns a second spawn path.
///
/// SwiftPM commands get `--scratch-path` pointed at the root's **one persistent
/// scratch** under `~/Library/Application Support/Allnighter/Lanes/<key>/scratch/`
/// (see `ExecutionLaneFlock.ensuredScratchPath`). Not per-attempt.
public struct ProjectVerificationService: Sendable {
    public static let defaultTimeoutSeconds = 600
    public static let outputTailCap = 4000

    private let commandRunner: CommandRunner
    private let perCommandTimeoutSeconds: Int
    private let now: @Sendable () -> Date

    public init(
        commandRunner: CommandRunner,
        perCommandTimeoutSeconds: Int = defaultTimeoutSeconds,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.commandRunner = commandRunner
        self.perCommandTimeoutSeconds = max(1, perCommandTimeoutSeconds)
        self.now = now
    }

    /// Run each declared proof command as a bounded subprocess at `repoRoot`.
    /// Does not acquire the execution lane — the relay/pilot harness holds (or
    /// re-enters) the lane around this call (PO-S03/S04).
    public func runProofs(
        commands: [String],
        repoRoot: String,
        scratchPath: String? = nil
    ) async -> [HarnessProofResult] {
        let cmds = commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cmds.isEmpty else { return [] }

        let scratch = scratchPath ?? ExecutionLaneFlock.ensuredScratchPath(repoRoot: repoRoot)
        var results: [HarnessProofResult] = []
        results.reserveCapacity(cmds.count)

        for raw in cmds {
            let command = Self.injectScratchPath(into: raw, scratchPath: scratch)
            let started = now()
            let result = await commandRunner.run(
                command: "/bin/sh",
                args: ["-c", command],
                stdin: nil,
                env: ProcessInfo.processInfo.environment,
                workingDirectory: repoRoot,
                timeout: .seconds(perCommandTimeoutSeconds)
            )
            let durationMs = max(0, Int(now().timeIntervalSince(started) * 1000))
            let combined = [result.stdout, result.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let launchNote = result.launchError.map { "launchError: \($0)" } ?? ""
            let tailSource = [combined, launchNote].filter { !$0.isEmpty }.joined(separator: "\n")
            let tail = String(tailSource.suffix(Self.outputTailCap))

            if result.timedOut {
                results.append(HarnessProofResult(
                    command: command,
                    exitCode: nil,
                    durationMs: durationMs,
                    outputTail: tail,
                    timedOut: true
                ))
                // Stop the chain on timeout — further commands would also be suspect
                // and the harness stamps endReason=proofTimeout from any timed-out entry.
                break
            }
            if let launchError = result.launchError {
                results.append(HarnessProofResult(
                    command: command,
                    exitCode: nil,
                    durationMs: durationMs,
                    outputTail: tail.isEmpty ? launchError : tail,
                    timedOut: false
                ))
                continue
            }
            let code = result.exitCode.map { Int($0) } ?? 1
            results.append(HarnessProofResult(
                command: command,
                exitCode: code,
                durationMs: durationMs,
                outputTail: tail,
                timedOut: false
            ))
        }
        return results
    }

    // MARK: - Scratch injection

    /// Inject `--scratch-path <scratch>` into SwiftPM invocations that lack one.
    /// Leaves non-`swift` commands unchanged. Idempotent when already present.
    public static func injectScratchPath(into command: String, scratchPath: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return command }
        // Already declared — never double-inject.
        if trimmed.contains("--scratch-path") { return command }

        // Match leading `swift` / path-to-swift (optional env prefix like `env FOO=bar swift …`).
        // Insert after the swift tool + first subcommand token when present
        // (`build`/`test`/`package`/…); otherwise after `swift` itself.
        let pattern = #"^(.*?\bswift(?:c)?)\b(\s+)([a-zA-Z0-9_-]+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return command
        }
        let ns = trimmed as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: full),
              match.numberOfRanges >= 2,
              match.range(at: 1).location != NSNotFound else {
            return command
        }
        // Only inject when the match is a real `swift` tool word, not a path fragment mid-arg.
        let toolRange = match.range(at: 1)
        let tool = ns.substring(with: toolRange)
        let toolBase = (tool as NSString).lastPathComponent
        guard toolBase == "swift" || toolBase == "swiftc" else { return command }

        let injection = " --scratch-path \(shellSingleQuote(scratchPath))"
        if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
            // After subcommand: `swift test` → `swift test --scratch-path …`
            let subEnd = match.range(at: 3).location + match.range(at: 3).length
            let prefix = ns.substring(to: subEnd)
            let suffix = ns.substring(from: subEnd)
            return prefix + injection + suffix
        }
        // Bare `swift` / `swiftc` with args or none.
        let toolEnd = toolRange.location + toolRange.length
        let prefix = ns.substring(to: toolEnd)
        let suffix = ns.substring(from: toolEnd)
        return prefix + injection + suffix
    }

    private static func shellSingleQuote(_ path: String) -> String {
        // POSIX-safe single-quote wrapping.
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - FR13 single-command façade (shared runner, no second spawn path)

extension RunProofRunner {
    /// PO-S04: multi-command harness proofs share `ProjectVerificationService`'s
    /// bounded-subprocess shape. Prefer that type for relay/pilot proof-of-record.
    public static var sharedOutputTailCap: Int { ProjectVerificationService.outputTailCap }
}
