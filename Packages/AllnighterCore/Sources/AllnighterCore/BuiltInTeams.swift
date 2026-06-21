import Foundation

/// The built-in lane-scoped teams — product assets shipped with Allnighter
/// (Team_Catalog §Built-in Team Manifest Index). Built-in ids are an
/// immutable public contract once used in history/reproduce commands; built-ins
/// cannot be edited directly — users duplicate them to customize.
public enum BuiltInTeams {

    public static let all: [TeamPreset] = [
        buildCore, buildBugHunt, buildGUIBugHunt, buildSecurityReview, buildSpecUpgrade, buildReleaseProof,
        defaultChat, executionPlaybook,
        designCore, designPremiumPolish, designConversionStudio, designRadicalDirections, designUsabilityTriage,
        copyCore, copyLandingPage,
        signalPostToProject, signalWhatToBuildNext
    ]

    private static let byID: [String: TeamPreset] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func team(_ id: String) -> TeamPreset? { byID[id] }
    public static func teams(in lane: WorkLane) -> [TeamPreset] { all.teams(in: lane) }

    // MARK: - Builders

    /// One worker row. Row id defaults to the skill id (unique within a team).
    private static func row(
        _ skillId: String, _ purpose: TeamWorkerPurpose,
        preferred: String? = nil, required: Bool = true,
        tags: [ModelCapabilityTag] = [], fallback: ModelFallbackPolicy = .strongestReady
    ) -> TeamWorkerSpec {
        TeamWorkerSpec(id: skillId, skillId: skillId, purpose: purpose,
                       preferredModelId: preferred, requiredCapabilityTags: tags,
                       fallbackPolicy: fallback, required: required)
    }

    /// Every built-in carries one mandatory Team Lead (synthesizer) — strongest
    /// ready model by default (no hard capability requirement, so one ready CLI can
    /// still report back). Effort scales the crew, never the Lead.
    private static func make(
        id: String, name: String, lane: WorkLane, output: TeamOutputKind,
        defaultEffort: EffortLevel, isDefault: Bool = false, description: String,
        scout: TeamWorkerSpec? = nil,
        rows: [TeamWorkerSpec], writer: String, dissent: DissentPolicy = .preserveDissent,
        lead: TeamLeadSpec? = nil,
        mutating: Bool = false, executionSourceId: String? = nil,
        typeTags: [String] = [], starters: [String] = []
    ) -> TeamPreset {
        TeamPreset(
            id: id, displayName: name, lane: lane, description: description, outputKind: output,
            mutating: mutating,
            executionSourceId: executionSourceId,
            defaultEffort: defaultEffort, isDefaultForLane: isDefault, scout: scout, workerSpecs: rows,
            lead: lead ?? TeamLeadSpec(skillId: writer, fallbackPolicy: .strongestReady, dissentPolicy: dissent),
            typeTags: typeTags, starterPrompts: starters, builtIn: true, version: 1)
    }

    /// The Signal scout row: an X-capable model (Grok today) grabs/distills the
    /// source FIRST. Falls back to any signal-lane model when Grok is absent, so a
    /// user with a different CLI still gets a scout (a degraded one — the customize
    /// surface warns when Grok is removed from this role).
    static let signalScoutGrok = TeamWorkerSpec(
        id: "signal_source_reader", skillId: "signal_source_reader", purpose: .answer,
        preferredModelId: "model_grok", fallbackPolicy: .laneCapable)

    /// Canonical interpreter preference: Grok (web-aware), GPT-5.5, then Gemini
    /// (strong at finding things online). The resolver fills the rest cheapest-first.
    static let signalInterpreterPreference = ["model_grok", "model_chatgpt", "model_gemini"]

    // MARK: - Code teams

    private static let codeAnswerPreferred = "model_cursor_composer_25"

    static let buildCore = make(
        id: "code_core", name: "Code Core", lane: .code, output: .plan, defaultEffort: .med, isDefault: true,
        description: "Turn a rough product/build prompt into an implementable plan with scope, architecture, risks, and proof.",
        rows: [
            row("product_architect", .answer, preferred: codeAnswerPreferred),
            row("proof_planner", .answer, preferred: codeAnswerPreferred),
            row("first_principles_builder", .answer, preferred: codeAnswerPreferred),
            row("code_maintainer", .answer, preferred: codeAnswerPreferred),
            row("scope_steward", .review),
            row("security_privacy_reviewer", .review),
            row("contrarian_reviewer", .review)
        ], writer: "plan_writer_build",
        starters: ["Turn this rough idea into an implementable plan with scope and proof.",
                   "Plan the smallest correct slice for <feature>."])

    static let buildBugHunt = make(
        id: "code_bug_hunt", name: "Bug Hunt", lane: .code, output: .bugPacket, defaultEffort: .high,
        description: "Find the real cause of broken behavior, map the blast radius, and plan the smallest correct fix.",
        rows: [
            row("bug_reproducer", .answer),
            row("truth_owner_mapper", .answer),
            row("correct_fix_planner", .answer),
            row("regression_guard", .answer, preferred: "model_chatgpt", fallback: .anyReady),
            row("trace_mapper", .answer),
            row("state_skeptic", .answer),
            row("change_impact_reviewer", .answer),
            row("user_impact_narrator", .review),
            row("contrarian_root_cause", .review)
        ], writer: "bug_packet_writer",
        starters: ["Find the real cause of <broken behavior> and plan the smallest correct fix."])

    static let buildGUIBugHunt = make(
        id: "code_gui_bug_hunt", name: "GUI Bug Hunt", lane: .code, output: .bugPacket, defaultEffort: .high,
        description: "Fix visible native-app breakage with rendered proof, layout-watcher review, and the right truth owner.",
        rows: [
            row("gui_bug_reproducer", .answer),
            row("gui_proof_guard", .answer),
            row("correct_fix_planner", .answer),
            row("regression_guard", .answer, preferred: "model_chatgpt", fallback: .anyReady),
            row("truth_owner_mapper", .answer),
            row("state_skeptic", .answer),
            row("change_impact_reviewer", .answer),
            row("gui_layout_reviewer", .review),
            row("contrarian_root_cause", .review)
        ], writer: "gui_bug_packet_writer")

    static let buildSecurityReview = make(
        id: "code_security_review", name: "Security Review", lane: .code, output: .securityRegister, defaultEffort: .high,
        description: "Evaluate privacy, credentials, permissions, exposure, and destructive operations with small-team shipping judgment.",
        rows: [
            row("boundary_mapper", .answer),
            row("secrets_reviewer", .answer),
            row("permission_reviewer", .answer),
            row("data_flow_reviewer", .answer),
            row("abuse_case_reviewer", .answer),
            row("dependency_injection_reviewer", .review),
            row("security_fix_prioritizer", .review)
        ], writer: "security_register_writer", dissent: .riskRegister)

    static let buildSpecUpgrade = make(
        id: "code_spec_upgrade", name: "Spec Upgrade", lane: .code,
        output: .specUpgrade, defaultEffort: .high,
        description: "Review and improve technical specs for any repo: sharpen scope, contracts, proof, risks, and implementation order without editing the doc.",
        scout: row("spec_outside_scout", .answer, preferred: "model_grok", fallback: .anyReady),
        rows: [
            row("spec_first_principles_reviewer", .answer),
            row("spec_contract_auditor", .answer),
            row("spec_proof_planner", .answer),
            row("spec_scope_steward", .answer),
            row("spec_hype_skeptic", .review),
            row("spec_contrarian_reviewer", .review)
        ], writer: "spec_upgrade_writer", dissent: .compareOptions,
        starters: ["Upgrade this technical spec. Review only; do not edit the doc."])

    static let buildReleaseProof = make(
        id: "code_release_proof", name: "Release Proof", lane: .code, output: .proofPacket, defaultEffort: .high,
        description: "Before a slice closes, prove that the owner-visible claim is actually true.",
        rows: [
            row("acceptance_auditor", .answer),
            row("test_runner_planner", .answer),
            row("risk_register", .review),
            row("edge_case_hunter", .answer),
            row("contract_drift_checker", .answer),
            row("demo_narrator", .review)
        ], writer: "proof_packet_writer", dissent: .riskRegister,
        starters: ["Prove this slice is actually done before I believe it."])

    private static let cursorPreferred = "model_cursor_composer_25"

    // MARK: - Unified run model teams

    /// Auto: the default route — one agent, mutating-allowed, no special-case code
    /// path. "Auto" because it picks your go-to agent and just runs it.
    static let defaultChat = make(
        id: "default_chat", name: "Auto", lane: .code, output: .plan, defaultEffort: .med,
        description: "The default route — your go-to agent in the repo, talk or build.",
        rows: [
            // Raw passthrough: the user's message reaches the agent unmodified, so a
            // default run equals running the CLI directly (never worse). No skill
            // wrapper, no synthesis — opinionated skills are for explicitly-picked presets.
            row(SkillCatalog.directChatSkillId, .answer, preferred: cursorPreferred, fallback: .sameSource)
        ],
        writer: SkillCatalog.directChatSkillId,
        lead: TeamLeadSpec(skillId: SkillCatalog.directChatSkillId, preferredModelId: cursorPreferred, fallbackPolicy: .sameSource),
        mutating: true, executionSourceId: "cursor_agent",
        starters: [])

    /// Execution Playbook as a built-in execution preset (docs/operations/Execution-Playbook.md).
    static let executionPlaybook = make(
        id: "execution_playbook", name: "Execution Playbook", lane: .code, output: .plan, defaultEffort: .high,
        description: "Disciplined senior-engineer loop: slice → narrow edits → proof → deslop → audit → commit.",
        rows: [
            row("execution_playbook", .answer, preferred: cursorPreferred, fallback: .sameSource)
        ],
        writer: "plan_writer_build",
        lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: cursorPreferred, fallbackPolicy: .sameSource),
        mutating: true, executionSourceId: "cursor_agent",
        starters: [ExecutionPlaybookPreset.prompt])

    // MARK: - Design teams

    static let designCore = make(
        id: "design_core", name: "Design Core", lane: .design, output: .designBoard, defaultEffort: .med, isDefault: true,
        description: "Turn a product/design prompt into several credible interface directions, then make the tradeoffs visible.",
        rows: [
            row("information_architect", .answer),
            row("interaction_designer", .answer),
            row("visual_system_designer", .answer),
            row("accessibility_reviewer", .review),
            row("brand_fit_reviewer", .review),
            // Image/design tile is optional: disables (not blocks) when no image model is ready.
            row("outlier_direction", .answer, required: false, tags: [.image], fallback: .anyReady),
            row("design_critic", .review)
        ], writer: "design_board_writer", dissent: .compareOptions)

    static let designPremiumPolish = make(
        id: "design_premium_polish", name: "Premium Polish", lane: .design, output: .polishBoard, defaultEffort: .high,
        description: "Make an existing surface feel expensive, intentional, and native without changing its product semantics.",
        rows: [
            row("hierarchy_sculptor", .answer),
            row("type_spacing_auditor", .answer),
            row("color_token_keeper", .answer),
            row("component_stylist", .answer),
            row("state_designer", .answer),
            row("polish_critic", .review)
        ], writer: "polish_board_writer",
        starters: ["Give me two more polished versions of <screen> — calmer, more intentional, native."])

    static let designConversionStudio = make(
        id: "design_conversion_studio", name: "Conversion Studio", lane: .design, output: .designBoard, defaultEffort: .high,
        description: "Improve a product/marketing surface so users understand the offer, trust it, and know what to do next.",
        rows: [
            row("offer_clarity", .answer),
            row("cta_path", .answer),
            row("friction_hunter", .answer),
            row("trust_builder", .answer),
            row("mobile_scanner", .answer),
            row("objection_finder", .review)
        ], writer: "conversion_board_writer")

    static let designRadicalDirections = make(
        id: "design_radical_directions", name: "Radical Directions", lane: .design, output: .designBoard, defaultEffort: .med,
        description: "Generate genuinely different design directions before the team converges too early.",
        rows: [
            row("minimal_direction", .answer),
            row("bold_direction", .answer),
            row("operational_direction", .answer),
            row("editorial_direction", .answer),
            row("native_app_direction", .answer),
            row("direction_critic", .review)
        ], writer: "direction_board_writer", dissent: .compareOptions)

    static let designUsabilityTriage = make(
        id: "design_usability_triage", name: "Usability Triage", lane: .design, output: .polishBoard, defaultEffort: .med,
        description: "Find why a surface feels confusing, slow, risky, or hard to repeat.",
        rows: [
            row("journey_mapper", .answer),
            row("control_ergonomics", .answer),
            row("navigation_reviewer", .answer),
            row("accessibility_reviewer", .review),
            row("cognitive_load_cutter", .review),
            row("state_feedback_reviewer", .review)
        ], writer: "usability_triage_writer")

    // MARK: - Copy teams (parity; full type packs owned by docs/phases/copy)

    static let copyCore = make(
        id: "copy_core", name: "Copy Core", lane: .copy, output: .copyBoard, defaultEffort: .med, isDefault: true,
        description: "Turn a copy prompt into clear, persuasive options grounded in the real offer.",
        rows: [
            row("offer_strategist", .answer),
            row("headline_writer", .answer),
            row("direct_response_writer", .answer),
            row("objection_hunter", .answer),
            row("cta_writer", .answer),
            row("proof_skeptic", .review),
            row("brand_voice", .review)
        ], writer: "copy_board_writer",
        starters: ["Write clearer, more persuasive options for <copy>."])

    static let copyLandingPage = make(
        id: "copy_landing_page", name: "Landing Page Team", lane: .copy, output: .copyBoard, defaultEffort: .high,
        description: "Rewrite a landing page so the offer is clear, trusted, and converts.",
        rows: [
            row("offer_strategist", .answer),
            row("headline_writer", .answer),
            row("cta_writer", .answer),
            row("direct_response_writer", .answer),
            row("objection_hunter", .answer),
            row("proof_skeptic", .review),
            row("brand_voice", .review)
        ], writer: "landing_copy_writer", typeTags: ["landing-page"])

    // MARK: - Signal teams (the outside-world scout craft)

    /// The atomic Signal card: turn one public post/thread/article/release into a
    /// Project-aware Insight with source receipts, freshness, and a skeptic pass.
    /// Non-mutating Signal team; public sources only.
    static let signalPostToProject = make(
        id: "signal_post_to_project", name: "Post-to-Project Signal", lane: .signal, output: .insight,
        defaultEffort: .med, isDefault: true,
        description: "Grok grabs and distills a public X post, thread, article, or release note, then several different models reason over it (triangulation) into a Project-aware Insight: what happened, why it matters here, with source receipts, freshness, and a skeptic pass.",
        scout: signalScoutGrok,
        rows: [
            // Three distinct minds reason over the scout's distilled source.
            TeamWorkerSpec(id: "signal_interpret", skillId: "signal_interpret", purpose: .answer,
                           count: 3, triangulate: true, triangulatePreferenceIds: signalInterpreterPreference),
            row("signal_skeptic", .review)
        ], writer: "insight_writer", dissent: .preserveDissent,
        starters: ["Paste a public X post or article link and ask how it applies to this project.",
                   "What does this release note mean for us?"])

    /// Scan recent outside-world change and recommend what to build next for this
    /// Project-aware Signal team; non-mutating.
    static let signalWhatToBuildNext = make(
        id: "signal_what_to_build_next", name: "What should we build next?", lane: .signal, output: .insight,
        defaultEffort: .high,
        description: "Scan what recently changed outside the repo and recommend the next build direction for this Project, with sourced reasoning, fit, and a skeptic pass.",
        rows: [
            row("signal_landscape_scanner", .answer),
            row("signal_project_fit", .answer),
            row("signal_product_ideas", .answer),
            row("signal_skeptic", .review)
        ], writer: "insight_writer", dissent: .compareOptions,
        starters: ["What should we build next given what changed outside the repo this week?"])
}
