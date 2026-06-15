import Foundation
import AllnighterCore

/// Built-in review lens profiles (RB2) and the final-spec profile (RB3). Lenses
/// carry an explicit **anti-echo** instruction: challenge, do not restate.
public extension BuiltInProfiles {
    static let antiEcho = "Do not restate or endorse the draft. Surface what is wrong, missing, or risky from your lens; if you find nothing material, say so briefly."

    static func lens(_ id: String, _ name: String, _ job: String) -> PromptProfile {
        PromptProfile(
            id: id, displayName: name, purpose: .reviewLens,
            template: "You are reviewing a draft implementation plan through one lens: \(name).\n\n\(job)\n\n\(antiEcho)\n\nGround your review in the prompt, the judge analysis, and the draft plan provided.",
            builtIn: true
        )
    }

    static var reviewLenses: [PromptProfile] {
        [
            lens("security_privacy", "Security & Privacy", "Find obvious security, privacy, permission, and data-leak gaps."),
            lens("code_maintainer", "Code Maintainer", "Keep the diff, architecture, and state ownership simple. Flag complexity."),
            lens("proof_qa", "Proof / QA", "Define the Works Test, proof wall, and the likely failure cases."),
            lens("ui_ux", "UI / UX", "Pressure-test the interaction model, empty/error states, and visual simplicity."),
            lens("customer_advocate", "Customer Advocate", "Ask whether a paying user cares and whether this solves the real pain."),
            lens("dissent_preserver", "Dissent Preserver", "Recover dissent or nuance the draft synthesis may have flattened. You get the raw seat answers — find what was lost."),
            lens("scope_discipline", "Scope discipline", "Challenge unnecessary stages, duplicated review, vague work orders, and runaway workflow shape. Do not estimate provider cost, quota, or runtime."),
            lens("writer_editor", "Writer / Editor", "Improve spec clarity, product language, and user-facing copy."),
            lens("coverage_audit", "Coverage Audit", "Meta-coverage: judge whether the original question is fully answered and name domain risks/edge cases the panel AND judge could have missed (rollback, i18n, abuse, rate limits). Do not restate the analysis's own blind spots.")
        ]
    }

    static var finalSpec: PromptProfile {
        PromptProfile(
            id: "final_spec_v1", displayName: "Final Spec (first principles)", purpose: .finalSpec,
            template: """
            You are the finalizer. From first principles, produce a decisive, executable implementation spec.
            You are given the prompt, raw seat answers, the structured judge analysis, the draft plan, and advisory reviews.
            Reviews are ADVISORY: adopt, partially adopt, reject, or defer each — and explain material decisions.
            Resolve EVERY contradiction in the analysis and rule on EVERY unique insight (preserve or reject, with a reason).

            Output Markdown with these sections:
            ## Final Spec
            ## Scope
            ## Non-goals
            ## Architecture and state ownership
            ## UX / user-facing behavior (or "n/a")
            ## Acceptance criteria
            ## Works Test and proof wall   (include concrete proof commands, or state you could not produce them)
            ## Decisions on panel contradictions
            ## Decisions on unique insights
            ## Decisions on review feedback
            ## Risks and open questions

            Decide; do not average. The spec must be executable by a coding agent with few questions.

            After the spec, output the exact sentinel \(Finalizer.decisionsDelimiter) on its own line, then a
            single fenced ```json block with your structured decisions:
            { "reviewDecisions": [{ "lensId": "...", "decision": "adopted|partial|rejected|deferred", "reason": "..." }],
              "contradictionDecisions": [{ "topic": "...", "resolution": "...", "reason": "..." }],
              "insightDecisions": [{ "insight": "...", "decision": "preserved|rejected", "reason": "..." }] }
            """,
            builtIn: true
        )
    }
}
