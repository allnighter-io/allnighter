import Foundation

/// Assembles the order for ONE elimination round (Try_Fix_Auto_Implement §Execution Prompt
/// Contract). Not a generic implementation prompt: try exactly the top hypothesis within its
/// boundary, run the proof, and — if it fails — STOP and report what it ruled out so the next
/// round can narrow. Pure + tested.
public enum FixAttemptPrompt {
    public static func assemble(
        originalReport: String, packet: FixPacket, hypothesis: FixPacket.Hypothesis
    ) -> String {
        var parts: [String] = ["# Fix attempt — one disciplined round"]

        parts.append("## Original bug report\n\(originalReport)")

        if let seam = packet.seam, !seam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("""
            ## Seam
            The bug crosses \(seam). A proof of one side is NOT enough — the change must make \
            the whole crossing work end to end.
            """)
        }

        parts.append("""
        ## The hypothesis to try (top of the ranked ladder)
        Cause: \(hypothesis.cause)
        Fix: \(hypothesis.fix)
        Fix boundary: \(hypothesis.fixBoundary)
        """)

        if !packet.ruledOut.isEmpty {
            parts.append("## Already ruled out — do NOT revisit\n"
                + packet.ruledOut.map { "- \($0)" }.joined(separator: "\n"))
        }

        parts.append("## Proof\n\(proofInstruction(packet))")

        parts.append("""
        ## Rules (strict)
        - Apply ONLY this hypothesis's fix, within its fix boundary. No broad cleanup, no \
        opportunistic refactor, no unrelated changes.
        - Inspect the repo BEFORE editing. If the code contradicts the hypothesis, STOP and \
        report the conflict — do not force the fix.
        - After editing, run the proof exactly as named and record its output and exit status.
        - If the proof FAILS, STOP. Report: what you changed, the proof output, and the single \
        smallest next theory (what this round ruled out). Do not try a second fix this round.
        - This is one round of an elimination loop, not a guaranteed repair. An honest \
        "tried X, it didn't work, here's what we now know" is a success for the loop.
        """)

        return parts.joined(separator: "\n\n")
    }

    private static func proofInstruction(_ packet: FixPacket) -> String {
        switch packet.proofMethod {
        case .command:
            return "Run this command EXACTLY after editing; capture its output and exit status:\n`\(packet.proofCommand ?? "")`"
        case .guiFixture:
            let watcher = packet.requiresLayoutWatcher ? " Then have the layout-watcher review the render." : ""
            return "Render the GUI fixture `\(packet.guiProofFixture ?? "")` and confirm the bug is gone in the render.\(watcher)"
        case .userObservation:
            return "There is no automated proof. After the fix, state PRECISELY what the user should now observe (and what they'd still see if it's broken) so they can confirm."
        }
    }
}
