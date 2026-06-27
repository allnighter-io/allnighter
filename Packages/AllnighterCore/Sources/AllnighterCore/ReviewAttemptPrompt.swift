import Foundation

/// Renders a read-bounded **advisory** order for code-review slices (docs/phases/code_review).
/// Review packets write findings only — no Swift edits. Pair_Programming_Team F1/F4.
public enum ReviewAttemptPrompt {
    public static func assemble(packet: WorkSlicePacket, nudge: String? = nil) -> String {
        var parts: [String] = ["# Code review — \(packet.sliceId)"]
        if !packet.title.isEmpty { parts.append("## Title\n\(packet.title)") }

        parts.append("""
        ## Mode
        READ-ONLY advisory review. Do **not** edit Swift or other source files.
        Do **not** grep or read outside the inlined sources below.
        """)

        if !packet.inlinedSources.isEmpty {
            let blocks = packet.inlinedSources.map { source -> String in
                var header = "### `\(source.path)`"
                if let range = source.lineRange, !range.isEmpty { header += " (lines \(range))" }
                return "\(header)\n```swift\n\(source.content)\n```"
            }.joined(separator: "\n\n")
            parts.append("## Inlined sources (complete — do not re-read)\n\(blocks)")
        } else if !packet.readPaths.isEmpty {
            let anchors = packet.readPaths.map { anchor -> String in
                var line = "- `\(anchor.path)`"
                if let symbol = anchor.symbol { line += " — \(symbol)" }
                if let range = anchor.lineRange { line += " (lines \(range))" }
                return line
            }.joined(separator: "\n")
            parts.append("""
            ## Read only (bounded)
            \(anchors)
            WARNING: sources were not inlined — read ONLY these paths once; no greps.
            """)
        }

        if !packet.resolvedSymbols.isEmpty {
            let symbols = packet.resolvedSymbols.map {
                "- `\($0.name)` — `\($0.signature)` at \($0.definedAt)"
            }.joined(separator: "\n")
            parts.append("## Resolved symbols (do not grep)\n\(symbols)")
        }

        parts.append("## Review lenses\n\(packet.intent)")

        let findingsPath = packet.touchAllowlist.first ?? "docs/phases/code_review/findings/\(packet.sliceId).md"
        parts.append("""
        ## Touch allowlist (strict)
        - `\(findingsPath)`
        Write ONLY this findings file. No opportunistic edits elsewhere.
        """)

        parts.append("## Required findings shape\n\(Self.findingsTemplate(sliceId: packet.sliceId))")

        parts.append("## Check (repo-owned)\n\(SliceAttemptPrompt.checkInstruction(packet.check))")

        parts.append("""
        ## Rules
        - Advisory only: rank findings P0 (invariant/security) / P1 (real win) / P2 (nit).
        - Every finding needs file:line evidence from the inlined sources.
        - End with **False alarms ruled out** and **Greps avoided** sections.
        - If no issues: say so explicitly under P0/P1; still write the findings file.
        """)

        if let nudge, !nudge.isEmpty {
            parts.append("## Nudge\n\(nudge)")
        }

        return parts.joined(separator: "\n\n")
    }

    public static func findingsTemplate(sliceId: String) -> String {
        """
        ```markdown
        # \(sliceId) — <title>

        ## Summary
        (one paragraph)

        ## Findings

        ### P0 — …
        - **Invariant:** …
        - **Evidence:** path:line
        - **Suggested fix:** …
        - **Suggested slice:** (optional one-line sprint title)

        ### P1 — …

        ## False alarms ruled out
        …

        ## Greps avoided
        (confirm no repo exploration)
        ```
        """
    }
}
