import Foundation

/// Adversarial verify pass — default P0 claims to FALSE unless upheld in source (code_review).
public enum ReviewVerifyPrompt {
  public static func assemble(packet: WorkSlicePacket, nudge: String? = nil) -> String {
    let reviewId = packet.sliceId.replacingOccurrences(of: "-verify", with: "")
    var parts: [String] = ["# Code review verify — \(packet.sliceId)"]
    if !packet.title.isEmpty { parts.append("## Title\n\(packet.title)") }

    parts.append("""
    ## Mode
    ADVERSARIAL VERIFY. Default every **P0** claim in the findings to **REJECTED** unless you \
    can cite counter-evidence from the inlined source OR confirm the exact failure mechanism in source.
    Do not edit Swift. Do not grep outside inlined material.
    """)

    if let findings = packet.inlinedFindings, !findings.isEmpty {
      parts.append("## Findings under review (from \(reviewId))\n```markdown\n\(findings)\n```")
    }

    if !packet.inlinedSources.isEmpty {
      let blocks = packet.inlinedSources.map { source -> String in
        var header = "### `\(source.path)`"
        if let range = source.lineRange, !range.isEmpty { header += " (lines \(range))" }
        return "\(header)\n```swift\n\(source.content)\n```"
      }.joined(separator: "\n\n")
      parts.append("## Inlined sources (authority — do not re-read)\n\(blocks)")
    }

    if !packet.resolvedSymbols.isEmpty {
      let symbols = packet.resolvedSymbols.map {
        "- `\($0.name)` — `\($0.signature)` at \($0.definedAt)"
      }.joined(separator: "\n")
      parts.append("## Resolved symbols\n\(symbols)")
    }

    parts.append("## Verify lenses\n\(packet.intent)")

    let outPath = packet.touchAllowlist.first
      ?? "docs/phases/code_review/findings/\(reviewId)-verified.md"
    parts.append("""
    ## Touch allowlist (strict)
    - `\(outPath)`
    Write ONLY this verified report.
    """)

    parts.append("## Required output shape\n\(Self.verifiedTemplate(reviewId: reviewId))")
    parts.append("## Check (repo-owned)\n\(SliceAttemptPrompt.checkInstruction(packet.check))")

    parts.append("""
    ## Rules
    - List each P0 from findings as **Uphold** or **Reject** with evidence.
    - Reject if the mechanism requires actor suspension that does not exist in source.
    - P1/P2: note only if materially wrong; do not rewrite the whole review.
  """)

    if let nudge, !nudge.isEmpty { parts.append("## Nudge\n\(nudge)") }
    return parts.joined(separator: "\n\n")
  }

  private static func verifiedTemplate(reviewId: String) -> String {
    """
    ```markdown
    # \(reviewId) — verified

    ## Summary
    (one paragraph: how many P0 upheld vs rejected)

    ## P0 adjudication

    ### P0 — <title> — Uphold | Reject
    - **Original claim:** …
    - **Verdict:** Uphold | Reject
    - **Evidence:** path:line or rejection reason

    ## P1 notes
    (optional)

    ## Greps avoided
    ```
    """
  }
}
