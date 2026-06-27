import Foundation

/// Renders a read-bounded executor order (Pair_Programming_Team F1/F4).
public enum SliceAttemptPrompt {
    public static func assemble(packet: WorkSlicePacket, nudge: String? = nil) -> String {
        var parts: [String] = ["# Work slice — \(packet.sliceId)"]
        if !packet.title.isEmpty { parts.append("## Title\n\(packet.title)") }

        if !packet.readPaths.isEmpty {
            let anchors = packet.readPaths.map { anchor -> String in
                var line = "- `\(anchor.path)`"
                if let symbol = anchor.symbol { line += " — \(symbol)" }
                if let range = anchor.lineRange { line += " (\(range))" }
                return line
            }.joined(separator: "\n")
            parts.append("## Read only (bounded)\n\(anchors)\nDo not grep or read outside this list.")
        }

        if !packet.resolvedSymbols.isEmpty {
            let symbols = packet.resolvedSymbols.map {
                "- `\($0.name)` — `\($0.signature)` at \($0.definedAt)"
            }.joined(separator: "\n")
            parts.append("## Resolved symbols (do not grep)\n\(symbols)")
        }

        parts.append("## Intent\n\(packet.intent)")

        if let skeleton = packet.skeleton, !skeleton.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("## Skeleton (guide only — not a literal patch)\n```\n\(skeleton)\n```")
        }

        let allowlist = packet.touchAllowlist.map { "- `\($0)`" }.joined(separator: "\n")
        parts.append("## Touch allowlist (strict)\n\(allowlist)\nEdit ONLY these paths. No opportunistic cleanup.")

        parts.append("## Check (repo-owned)\n\(Self.checkInstruction(packet.check))")

        parts.append("""
        ## Rules
        - One bounded slice: small reads, narrow writes, no repo-wide exploration.
        - Do not read `AGENTS.md`, phase boards, or unrelated files.
        - After editing, run the check exactly as named and record output + exit status.
        - If the check fails, STOP and report what you changed and the check output.
        """)

        if let nudge, !nudge.isEmpty {
            parts.append("## Nudge\n\(nudge)")
        }

        return parts.joined(separator: "\n\n")
    }

    public static func checkInstruction(_ check: WorkSlicePacket.Check) -> String {
        switch check.method {
        case .command:
            return "Run this command EXACTLY after editing; capture output and exit status:\n`\(check.command ?? "")`"
        case .guiFixture:
            return "Render GUI fixture `\(check.fixture ?? "")` and confirm the slice intent holds in the render."
        case .userObservation:
            return "No automated check. State precisely what the user should observe after your edit."
        }
    }
}
