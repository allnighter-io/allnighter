import Foundation

/// Planner (Composer) order after executor attempts are exhausted (Pair_Programming_Team PPT-S14).
public enum PlannerTakeoverPrompt {
    public struct Context: Sendable, Equatable {
        public var executorAttempts: Int
        public var lastTerminal: String
        public var checkExitCode: Int32?
        public var checkStdoutTail: String?
        public var lastWorkerOutput: String?

        public init(
            executorAttempts: Int,
            lastTerminal: String,
            checkExitCode: Int32? = nil,
            checkStdoutTail: String? = nil,
            lastWorkerOutput: String? = nil
        ) {
            self.executorAttempts = executorAttempts
            self.lastTerminal = lastTerminal
            self.checkExitCode = checkExitCode
            self.checkStdoutTail = checkStdoutTail
            self.lastWorkerOutput = lastWorkerOutput
        }
    }

    public static func assemble(packet: WorkSlicePacket, context: Context) -> String {
        var parts = [
            "# Planner takeover — slice \(packet.sliceId)",
            "The free executor failed \(context.executorAttempts) times on this slice. You are the planner seat — implement the slice directly.",
        ]
        if !packet.title.isEmpty { parts.append("## Title\n\(packet.title)") }
        parts.append("## Intent\n\(packet.intent)")

        if !packet.readPaths.isEmpty {
            let anchors = packet.readPaths.map { anchor -> String in
                var line = "- `\(anchor.path)`"
                if let symbol = anchor.symbol { line += " — \(symbol)" }
                if let range = anchor.lineRange { line += " (\(range))" }
                return line
            }.joined(separator: "\n")
            parts.append("## Read only (bounded)\n\(anchors)")
        }

        if !packet.resolvedSymbols.isEmpty {
            let symbols = packet.resolvedSymbols.map {
                "- `\($0.name)` — `\($0.signature)` at \($0.definedAt)"
            }.joined(separator: "\n")
            parts.append("## Resolved symbols\n\(symbols)")
        }

        if let skeleton = packet.skeleton, !skeleton.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("## Skeleton (guide only)\n```\n\(skeleton)\n```")
        }

        let allowlist = packet.touchAllowlist.map { "- `\($0)`" }.joined(separator: "\n")
        parts.append("## Touch allowlist (strict)\n\(allowlist)\nEdit ONLY these paths.")

        parts.append("## Check (must pass)\n\(SliceAttemptPrompt.checkInstruction(packet.check))")

        parts.append("""
        ## Failure context
        - Last terminal: \(context.lastTerminal)
        - Executor attempts: \(context.executorAttempts)
        """)

        if let code = context.checkExitCode {
            parts.append("- Check exit code: \(code)")
        }
        if let tail = context.checkStdoutTail?.trimmingCharacters(in: .whitespacesAndNewlines), !tail.isEmpty {
            parts.append("## Last check output\n```\n\(tail)\n```")
        }
        if let worker = context.lastWorkerOutput?.trimmingCharacters(in: .whitespacesAndNewlines), !worker.isEmpty {
            parts.append("## Last executor output\n```\n\(worker)\n```")
        }

        parts.append("""
        ## Rules
        - Implement the slice intent within the allowlist. No repo-wide refactors.
        - Run the check command after editing; it must exit 0.
        - Do not spawn sub-slices or rewrite the queue — finish this unit.
        """)

        return parts.joined(separator: "\n\n")
    }
}
